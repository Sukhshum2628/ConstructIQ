"""
Agent tools for the Construction Project Analyst.

Each tool is built per-request with `project_id` captured in a closure, so the
LLM only chooses *which* tool to call — it never has to pass the id as an
argument (small models are unreliable at that). Tools read live data from the
same Firestore client the RAG engine uses (`rag_engine.db`), and fall back to
realistic mock strings when Firestore is unavailable or AGENT_MOCK=1 (Step 1:
"run the basic agent locally with mock tool responses").
"""

import os
from datetime import datetime, timezone

from langchain_core.tools import tool
from firebase_admin import firestore

from modules.rag_engine import rag_engine


def _db():
    return rag_engine.db  # firestore client, or the string "MOCK"


def _is_mock() -> bool:
    return os.getenv("AGENT_MOCK") == "1" or _db() == "MOCK"


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _as_dt(v) -> datetime:
    """Firestore timestamps read back as tz-aware datetimes; be defensive."""
    if isinstance(v, datetime):
        return v if v.tzinfo else v.replace(tzinfo=timezone.utc)
    return _now()


def _w(m: dict) -> float:
    x = m.get("weight", 1.0) or 1.0
    return 1.0 if x <= 0 else float(x)


def make_tools(project_id: str):
    """Return the agent's tools, each bound to `project_id`."""

    @tool
    def get_milestone_status() -> str:
        """Schedule health for the current project: overall planned vs actual
        percent complete and any overdue milestones. Use this for questions about
        whether the project is on track / on schedule / delayed."""
        if _is_mock():
            return ("Schedule (mock): overall actual 58.0% vs planned 60.0% "
                    "(2.0% behind). Overdue: 'Foundation' — planned end "
                    "2026-05-01, 80% done.")
        db = _db()
        docs = db.collection("projects").document(project_id) \
                 .collection("milestones").get()
        ms = [d.to_dict() for d in docs]
        if not ms:
            return "No milestones have been defined for this project."

        now = _now()
        tw = sum(_w(m) for m in ms)
        if tw == 0:
            return "Milestones exist but have no weight; cannot compute schedule."

        actual = sum(_w(m) * (float(m.get("progress", 0)) / 100) for m in ms) / tw * 100

        planned = 0.0
        overdue = []
        for m in ms:
            ps, pe = _as_dt(m.get("plannedStart")), _as_dt(m.get("plannedEnd"))
            span = (pe - ps).total_seconds()
            if span <= 0:
                frac = 0.0 if now < ps else 1.0
            else:
                frac = max(0.0, min(1.0, (now - ps).total_seconds() / span))
            planned += _w(m) * frac
            if float(m.get("progress", 0)) < 100 and pe < now:
                overdue.append(f"'{m.get('name', 'Milestone')}' "
                               f"(due {pe.date()}, {float(m.get('progress', 0)):.0f}% done)")
        planned = planned / tw * 100
        delta = actual - planned
        verdict = "on track" if delta >= -2 else "behind schedule"
        line = (f"Schedule: overall actual {actual:.1f}% vs planned {planned:.1f}% "
                f"({delta:+.1f} pts → {verdict}). {len(ms)} milestone(s).")
        if overdue:
            line += " Overdue: " + "; ".join(overdue) + "."
        return line

    @tool
    def get_cost_deviation() -> str:
        """Cost health for the current project: estimated vs invoiced spend,
        overall deviation severity, the XGBoost overrun probability, and the
        worst material deviations. Use for questions about budget, cost overrun,
        spend, or material deviations."""
        if _is_mock():
            return ("Cost (mock): CAD estimate ₹12,40,000; invoiced to date "
                    "₹4,10,000. Deviation severity CRITICAL; overrun probability "
                    "72%. Worst: bricks +66% vs pro-rated plan, cement +18%.")
        db = _db()
        base = db.collection("projects").document(project_id)
        ests = base.collection("estimates") \
                   .order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).get()
        bills = base.collection("vendorBills").get()
        dev = base.collection("deviations").document(f"live_{project_id}").get()

        rates = {"cement": 450.0, "bricks": 12.0, "steel": 75.0,
                 "sand": 60.0, "aggregate": 85.0}
        est_cost = 0.0
        if ests:
            for k, v in (ests[0].to_dict().get("estimatedMaterials", {}) or {}).items():
                qty = float(v.get("quantity", 0)) if isinstance(v, dict) else 0
                for rk, rv in rates.items():
                    if rk in k.lower():
                        est_cost += rv * qty
                        break
        invoiced = sum(float(b.to_dict().get("amount", 0)) for b in bills)

        d = dev.to_dict() if dev.exists else {}
        severity = str(d.get("overallSeverity", "normal")).upper()
        overrun = float(d.get("mlOverrunProbability", 0.0)) * 100
        worst = []
        for name, info in (d.get("breakdown", {}) or {}).items():
            if isinstance(info, dict) and "deviationPct" in info:
                worst.append((name, float(info.get("deviationPct", 0))))
        worst.sort(key=lambda x: abs(x[1]), reverse=True)
        worst_str = ", ".join(f"{n} {p:+.0f}%" for n, p in worst[:3]) or "none recorded"
        return (f"Cost: CAD estimate ₹{est_cost:,.0f}; invoiced to date "
                f"₹{invoiced:,.0f}. Deviation severity {severity}; overrun "
                f"probability {overrun:.0f}%. Worst materials vs pro-rated plan: "
                f"{worst_str}.")

    @tool
    def get_recent_logs() -> str:
        """Recent site resource-consumption logs for the current project (last 5
        entries). Use to explain *why* deviations are happening or to summarise
        recent on-site activity."""
        if _is_mock():
            return ("Recent logs (mock): 2026-05-10 bricks 600, cement 25; "
                    "2026-05-09 bricks 550, cement 22. Notes: brickwork ahead of "
                    "plan on the east wing.")
        db = _db()
        logs = db.collection("projects").document(project_id) \
                 .collection("resourceLogs") \
                 .order_by("date", direction=firestore.Query.DESCENDING).limit(5).get()
        rows = []
        for l in logs:
            d = l.to_dict()
            rows.append(f"{d.get('date')}: {d.get('materialUsage', d.get('materials', {}))}"
                        f" — {d.get('notes', '')}".strip())
        return "Recent logs:\n" + "\n".join(rows) if rows else "No resource logs yet."

    @tool
    def get_weather_impact() -> str:
        """Recent weather conditions relevant to site work for the current
        project. Use when assessing delays that may be weather-driven."""
        # Weather is currently captured on-device, not persisted server-side, so
        # this returns an indicative summary. Wire to a weather API or a
        # `weatherLogs` subcollection when that data is available server-side.
        return ("Weather (indicative): 3 rain days in the last 10, ~1 likely "
                "lost work day. Not yet wired to a live server-side source.")

    return [get_milestone_status, get_cost_deviation, get_recent_logs,
            get_weather_impact]
