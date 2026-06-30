import os
import json
import hashlib
import traceback
import re
import firebase_admin
from firebase_admin import firestore, credentials
from modules.vector_db_manager import get_db_manager
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

class RAGEngine:
    def __init__(self):
        self._db = None
        self._nvidia_client = None
        self._nvidia_model = os.getenv('NVIDIA_MODEL', 'meta/llama-3.1-8b-instruct')
        self.PROMPT_TEMPLATE = """You are an expert construction project analyst assistant for ConstructIQ.
Your task is to answer the engineer's question clearly and accurately using the project context provided below.

The context contains:
1. Live Project Metadata (budget, target costs, spent/invoiced, timeline elapsed/remaining).
2. --- REAL-TIME DEVIATION METRICS --- : These are pre-calculated by the advanced XGBoost machine learning model and CPWD/deviation analyzer. This contains the definitive overall severity, overrun probability, and detailed material deviations (Actual vs. Pro-rated Budgeted with percentage deviations).
3. Recent Resource Logs: A list of recent consumption logs.

CRITICAL INSTRUCTIONS:
- When asked about deviations, overruns, or consumption status, DO NOT attempt to recalculate them manually. DO NOT claim that actual quantities are not available in context. Instead, refer directly to the '--- REAL-TIME DEVIATION METRICS ---' section.
- TIMELINE REASONING: Note the elapsed timeline progress (e.g., 10 days out of 90 days). NEVER compare the cumulative actual consumed quantity directly to the lifetime total budgeted quantity to claim there is an underrun, nor claim that a low actual quantity means a deviation is incorrect. Compare the Actual Consumed directly to the "Pro-rated Planned" quantity for the elapsed duration.
- State clearly that the deviation percentage is calculated against this pro-rated timeline expectation, which explains why a project that has just started can still show a critical deviation (e.g. if brick usage is 66% above what was planned for the first 10 days).
- Summarize the ML overrun probability and the material breakdown to give a clear, professional, and actionable overview of the project's health.
- Explain how recent resource logs align with or explain these deviation metrics.

Context:
{context}

Question: {question}
Answer:"""

    @property
    def db(self):
        if self._db is None:
            self._db = self._init_firebase()
        return self._db

    @property
    def nvidia_client(self):
        if self._nvidia_client is None:
            self._nvidia_client = OpenAI(
                base_url=os.getenv('NVIDIA_BASE_URL', 'https://integrate.api.nvidia.com/v1'),
                api_key=os.getenv('NVIDIA_API_KEY'),
            )
        return self._nvidia_client

    def _init_firebase(self):
        if firebase_admin._apps:
            return firestore.client()
        
        # Priority 1: JSON string from environment variable (Railway/Cloud)
        creds_json = os.getenv('FIREBASE_CREDENTIALS_JSON')
        if creds_json:
            try:
                creds_dict = json.loads(creds_json)
                cred = credentials.Certificate(creds_dict)
                firebase_admin.initialize_app(cred)
                print("Firebase initialized via FIREBASE_CREDENTIALS_JSON env var")
                return firestore.client()
            except Exception as e:
                print(f"Failed to init Firebase from env var: {e}")
        
        # Priority 2: Local file (development only)
        # Check both local path and module-relative path
        service_account_paths = [
            'service_account.json',
            os.path.join(os.path.dirname(__file__), '..', 'service_account.json')
        ]
        
        for path in service_account_paths:
            if os.path.exists(path):
                try:
                    cred = credentials.Certificate(path)
                    firebase_admin.initialize_app(cred)
                    print(f"Firebase initialized via {path}")
                    return firestore.client()
                except Exception as e:
                    print(f"Failed to load {path}: {e}")
        
        print("WARNING: No Firebase credentials found. RAG runs in mock mode.")
        return "MOCK"

    @property
    def db_manager(self):
        return get_db_manager()

    def _ensure_indexed(self, project_id: str):
        """Re-index if collection is empty or missing (Railway persistence helper)."""
        if os.getenv("RENDER_EXTERNAL_URL"):
            # On low-RAM Render Free tier, we bypass local Chroma indexing completely to stay under 512MB RAM
            return
        try:
            collection = self.db_manager.client.get_collection(
                name=f"project_{project_id}"
            )
            count = collection.count()
            if count == 0:
                print(f"Collection empty for {project_id}, re-indexing...")
                self.index_project_data(project_id)
        except Exception:
            # Collection does not exist yet
            print(f"Collection missing for {project_id}, indexing...")
            self.index_project_data(project_id)

    def index_project_data(self, project_id: str):
        """Indexes estimates and last 30 logs for a specific project."""
        if self.db == "MOCK":
            mock_chunks = [
                f"Project Estimate (Current): {{'bricks': 5000, 'cement': 200}} Status: published",
                "On 2026-03-20, Site Engineer logged: {'bricks': 500, 'cement': 20}. Notes: Standard brickwork starting.",
                "On 2026-03-21, Site Engineer logged: {'bricks': 600, 'cement': 25}. Notes: Progress steady.",
                "Deviation Report: overallSeverity: critical, breakdown: {'bricks': 0.15}"
            ]
            self._save_to_vector_db(project_id, mock_chunks)
            return len(mock_chunks)

        # Use self.db (the initialized client). Each read projects only the
        # fields used below (.select on queries, field_paths on the single doc),
        # so we don't pull whole documents over the wire.
        project_doc = self.db.collection("projects").document(project_id).get(
            field_paths=["name", "status", "plannedBudget", "projectType", "durationDays"])
        estimates = self.db.collection("projects").document(project_id).collection("estimates").order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).select(
            ["estimatedMaterials", "generatedAt", "labour", "totalLabourDays"]).get()
        logs = self.db.collection("projects").document(project_id).collection("resourceLogs").order_by("date", direction=firestore.Query.DESCENDING).limit(30).select(
            ["date", "loggedBy", "materialUsage", "materials", "equipment", "notes"]).get()
        deviations = self.db.collection("projects").document(project_id).collection("deviations").order_by("createdAt", direction=firestore.Query.DESCENDING).limit(5).select(
            ["overallSeverity", "breakdown", "mlOverrunProbability", "createdAt"]).get()
        vendor_bills = self.db.collection("projects").document(project_id).collection("vendorBills").order_by("date", direction=firestore.Query.DESCENDING).limit(10).select(
            ["date", "vendorName", "items", "amount", "billId"]).get()

        chunks = []
        if project_doc.exists:
            p = project_doc.to_dict()
            chunks.append(f"Project Overview: Name: {p.get('name')}, Status: {p.get('status')}, Planned Budget: {p.get('plannedBudget', 0)}. Sector: {p.get('projectType')}. Duration: {p.get('durationDays')} days.")

        if estimates:
            est_data = estimates[0].to_dict()
            chunks.append(f"Project Estimate (Current): {est_data.get('estimatedMaterials', {})} generated on {est_data.get('generatedAt')}. Labour: {est_data.get('labour', {})}. Total Labour Days: {est_data.get('totalLabourDays')}")
        for bill in vendor_bills:
            b = bill.to_dict()
            chunks.append(f"Vendor Bill/Invoice Delivery: On {b.get('date')}, vendor {b.get('vendorName')} delivered items: {b.get('items', [])}. Total Amount: {b.get('amount')}. Bill ID: {b.get('billId')}")
        for log in logs:
            l = log.to_dict()
            chunks.append(f"On {l.get('date')}, {l.get('loggedBy')} logged: {l.get('materialUsage', l.get('materials', {}))}. Equipment: {l.get('equipment')}. Notes: {l.get('notes')}")
        for dev in deviations:
            d = dev.to_dict()
            chunks.append(f"Deviation Report: overallSeverity: {d.get('overallSeverity')}, breakdown: {d.get('breakdown')}, Overrun Probability: {d.get('mlOverrunProbability')}")

        if chunks:
            self._save_to_vector_db(project_id, chunks)
        return len(chunks)

    @staticmethod
    def _chunk_hash(text: str) -> str:
        """Stable SHA-256 of a chunk's content — used as both the cache key and
        the vector's id, so identical content never gets re-embedded."""
        return hashlib.sha256(text.encode("utf-8")).hexdigest()

    def _save_to_vector_db(self, project_id: str, chunks: list):
        """Content-hash cache layer in FRONT of the embedding step.

        Instead of deleting the collection and re-embedding everything, we embed
        only chunks whose content hash isn't already stored, and remove vectors
        whose content is gone. Chunking + the NIM embedding function (invoked by
        collection.add) are unchanged.
        """
        collection_name = f"project_{project_id}"
        collection = self.db_manager.client.get_or_create_collection(
            name=collection_name,
            embedding_function=self.db_manager.embedding_fn,
        )

        # Desired state: hash -> text (dedupes identical chunks in this batch).
        desired = {self._chunk_hash(c): c for c in chunks if c and c.strip()}

        def _vid(h: str) -> str:
            return f"{project_id}_{h}"

        # Existing state: fetch ids + metadata only (no documents/embeddings), so
        # the cache check stays cheap. The content_hash lives in metadata.
        try:
            existing = collection.get(include=["metadatas"])
            existing_ids = set(existing.get("ids", []))
        except Exception:
            existing_ids = set()

        # New content is the ONLY thing we embed; everything else is reused.
        to_add = {h: t for h, t in desired.items() if _vid(h) not in existing_ids}
        # Stale = previously embedded content no longer present → drop it.
        desired_ids = {_vid(h) for h in desired}
        to_delete = [i for i in existing_ids if i not in desired_ids]

        if to_delete:
            collection.delete(ids=to_delete)
        if to_add:  # collection.add triggers embedding for these chunks only
            collection.add(
                documents=list(to_add.values()),
                metadatas=[{"project_id": project_id, "content_hash": h}
                           for h in to_add],
                ids=[_vid(h) for h in to_add],
            )
        reused = len(desired) - len(to_add)
        print(f"[RAG cache] project={project_id}: {len(to_add)} embedded (new), "
              f"{reused} reused (cached), {len(to_delete)} removed (stale)")

    def get_answer(self, project_id: str, question: str):
        # STEP 4 FIX: Re-index if collection is missing/empty (persistence helper)
        self._ensure_indexed(project_id)
        
        base_context = ""
        try:
            if self.db != "MOCK":
                p_doc = self.db.collection("projects").document(project_id).get(
                    field_paths=["name", "status", "plannedBudget", "durationDays"])
                if p_doc.exists:
                    p = p_doc.to_dict()
                    
                    # -- LIVE AGGREGATIONS --
                    ests = self.db.collection("projects").document(project_id).collection("estimates").order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).select(
                        ["estimatedMaterials", "generatedAt"]).get()
                    # Only the amount is summed below — project just that field.
                    bills = self.db.collection("projects").document(project_id).collection("vendorBills").select(["amount"]).get()
                    logs = self.db.collection("projects").document(project_id).collection("resourceLogs").order_by("date", direction=firestore.Query.DESCENDING).limit(5).select(
                        ["date", "materialUsage"]).get()
                    dev_snap = self.db.collection("projects").document(project_id).collection("deviations").document(f"live_{project_id}").get(
                        field_paths=["overallSeverity", "mlOverrunProbability", "breakdown"])
                    
                    # Compute CAD estimated cost using hardcoded flutter rates
                    est_cost = 0.0
                    rates = {'cement': 450.0, 'bricks': 12.0, 'steel': 75.0, 'sand': 60.0, 'aggregate': 85.0}
                    if ests:
                        est_mats = ests[0].to_dict().get('estimatedMaterials', {})
                        for m_key, m_val in est_mats.items():
                            qty = m_val.get('quantity', 0)
                            name = m_key.lower()
                            for r_k, r_v in rates.items():
                                if r_k in name:
                                    est_cost += r_v * float(qty)
                                    break
                    
                    # Compute Invoiced Total
                    inv_total = sum(b.to_dict().get('amount', 0) for b in bills)
                    
                    recent_logs = [f"{l.to_dict().get('date')}: {l.to_dict().get('materialUsage', {})}" for l in logs]

                    # Retrieve pre-computed deviations uploaded directly from phone's DeviationCalculator
                    dev_data = {}
                    if dev_snap.exists:
                        dev_data = dev_snap.to_dict()

                    severity = dev_data.get('overallSeverity', 'normal').upper()
                    ml_overrun_probability = float(dev_data.get('mlOverrunProbability', 0.0))
                    breakdown = dev_data.get('breakdown', {})

                    log_count = len(logs)
                    duration_days = int(p.get('durationDays', 90))
                    effective_days = log_count if log_count > 0 else 1
                    timeline_pct = (effective_days / duration_days) * 100

                    base_context = (
                        f"[CRITICAL LIVE CONTEXT SETTINGS - PRE-COMPUTED DEVIATIONS & ESTIMATES]\n"
                        f"Project Name: {p.get('name')}\n"
                        f"Status: {p.get('status')}\n"
                        f"User's Target Budget: ₹{p.get('plannedBudget', 0)}\n"
                        f"CAD Estimated Material Cost: ₹{est_cost:,.2f}\n"
                        f"Total Spent/Invoiced To Date: ₹{inv_total:,.2f}\n"
                        f"Project Duration: {duration_days} days\n"
                        f"Timeline Progress: {effective_days} days elapsed out of {duration_days} days ({timeline_pct:.1f}% timeline complete)\n\n"
                        f"--- REAL-TIME DEVIATION METRICS (FROM PHONE DEVIATION CALCULATOR) ---\n"
                        f"Overall Deviation Severity: {severity}\n"
                        f"Calculated XGBoost Overrun Probability: {ml_overrun_probability * 100:.1f}%\n"
                        f"Detailed Material Deviations Breakdown:\n"
                    )
                    
                    for m_name, m_info in breakdown.items():
                        if isinstance(m_info, dict) and 'estimated' in m_info:
                            est = float(m_info.get('estimated', 0.0))
                            act = float(m_info.get('actual', 0.0))
                            prorated_est = (est / duration_days) * effective_days
                            dev_pct = float(m_info.get('deviationPct', 0.0))
                            unit = m_info.get('unit', '')
                            base_context += (
                                f"  - {m_name.capitalize()}: Actual Consumed = {act:.1f} {unit}, "
                                f"Pro-rated Planned = {prorated_est:.1f} {unit} (for {effective_days}/{duration_days} days), "
                                f"Lifetime Total Budgeted = {est:.1f} {unit}, "
                                f"Deviation from Pro-rated Planned = {dev_pct:+.1f}%\n"
                            )
                    base_context += (
                        f"\nRecent Resource Logs (Consumption): {recent_logs}\n"
                        f"========================================================\n\n"
                    )
        except Exception as e:
            print(f"Failed to fetch live project metadata: {e}")

        # Vector retrieval is now safe on Render: embeddings are computed by the
        # hosted NIM API (no local model), so this stays well under the 512MB
        # limit. Fall back to the live Firestore context if retrieval fails.
        try:
            collection = self.db_manager.client.get_or_create_collection(
                name=f"project_{project_id}",
                embedding_function=self.db_manager.embedding_fn
            )
            results = collection.query(query_texts=[question], n_results=10)
            docs = (results.get('documents') or [[]])[0]
            context = base_context + "\n".join(docs)
        except Exception as e:
            print(f"Vector retrieval skipped, using live context only: {e}")
            context = base_context

        # Stay completely under 512MB RAM on Render Free Tier by doing direct API calls using live context!
        # Avoid loading 350MB+ sentence-transformers in memory.
        if os.getenv('NVIDIA_API_KEY'):
            return self._call_llm(context=context, question=question)
        return "AI assistant is not configured. Please set NVIDIA_API_KEY in the server .env file."

    def _call_llm(self, context: str, question: str):
        prompt = self.PROMPT_TEMPLATE.format(context=context, question=question)
        try:
            response = self.nvidia_client.chat.completions.create(
                model=self._nvidia_model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.2,
                max_tokens=1024,
            )
            return response.choices[0].message.content
        except Exception as e:
            print(f"NVIDIA NIM LLM error: {e}")
            traceback.print_exc()
            return f"AI assistant is temporarily unavailable. Raw context:\n\n{context[:500]}..."

    def _extract_json_from_text(self, text: str) -> dict:
        """Helper to extract JSON from potentially verbose LLM output."""
        try:
            # Try direct load first
            return json.loads(text.strip())
        except json.JSONDecodeError:
            # Try to find the first '{' and last '}'
            match = re.search(r"(\{.*\})", text, re.DOTALL)
            if match:
                try:
                    return json.loads(match.group(1))
                except json.JSONDecodeError:
                    pass
            
            # If all fails, return a synthetic response
            return {
                "isPlausible": True,
                "reason": f"AI responded with text instead of JSON: {text[:200]}...",
                "confidence": 0.5
            }

    def validate_geometry(self, geometry: dict) -> dict:
        total_wall_len = geometry.get('totalWallLength', 0)
        total_floor_area = geometry.get('totalFloorArea', 0)
        if total_floor_area <= 0:
            return {"isPlausible": False, "reason": "Zero or negative floor area detected.", "confidence": 1.0}
        ratio = total_wall_len / total_floor_area
        
        if not os.getenv('NVIDIA_API_KEY'):
            is_ok = 0.15 < ratio < 3.5
            return {"isPlausible": is_ok, "reason": "Rule-based heuristic check.", "confidence": 0.7}

        prompt = f"""You are a civil engineering validator. 
Analyze if these residential wall dimensions are physically plausible.
- Total Wall Length: {total_wall_len}m
- Total Floor Area: {total_floor_area}m2
- Ratio: {ratio:.2f}

Return ONLY a JSON object with this exact structure:
{{
  "isPlausible": bool,
  "reason": "Detailed engineering justification",
  "confidence": 0.95
}}
NO EXPLANATION outside the JSON block."""

        try:
            response = self.nvidia_client.chat.completions.create(
                model=self._nvidia_model,
                messages=[{"role": "user", "content": prompt}],
                temperature=0.1
            )
            raw_content = response.choices[0].message.content
            return self._extract_json_from_text(raw_content)
        except Exception as e:
            print(f"Validation AI error: {e}")
            traceback.print_exc()
            return {"isPlausible": True, "reason": "AI validation offline (Presumed OK)", "confidence": 0.5}

rag_engine = RAGEngine()

# Global exposure for simple imports (as requested in other modules)
def validate_geometry(geometry: dict) -> dict:
    return rag_engine.validate_geometry(geometry)
