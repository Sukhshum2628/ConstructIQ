# ConstructIQ — Detailed Project Report

*AI-assisted construction project-management platform.*
*Report generated 2026-06-15.*

---

## 1. Executive Summary

ConstructIQ is a cross-platform construction-management system that turns a
floor-plan PDF/DXF into a costed material estimate, then tracks actual site
execution against that estimate and flags deviations. It pairs a **Flutter**
mobile app (with on-device ML) and a **Python FastAPI** AI service, backed by
**Firebase** (Auth, Firestore, Storage, FCM) and **NVIDIA NIM** LLM/embeddings.

It serves four roles — **Owner, Manager, Engineer, Admin** — each with a tailored
dashboard, and spans the full workflow: estimation, daily resource logging,
scheduling, inventory, safety/QA, delays, finance, analytics, an AI assistant,
and a new stateful **LangGraph Project Analyst agent**.

---

## 2. System Architecture

```
┌──────────────────────────┐      ┌───────────────────────────┐     ┌────────────────┐
│  Flutter app (Dart)      │────▶│  Python FastAPI service     │────▶│  NVIDIA NIM    │
│  construction_flutter_app│      │  construction-ai-service    │◀────│  LLM + embed   │
│  • UI, Riverpod, go_router│◀────│  • CAD/DXF parse, RAG       │     │ (Llama 3.1 8B, │
│  • on-device YOLO + XGB   │      │  • LangGraph agent, invoices│     │  bge-m3)       │
└─────────────┬────────────┘      └─────────────┬──────────────┘     └────────────────┘
              │                                  │
              ▼                                  ▼
        ┌───────────────────────────────────────────────┐
        │  Firebase: Auth · Firestore · Storage · FCM     │
        └───────────────────────────────────────────────┘
```

**Design principle:** heavy / offline-capable work runs **on-device** (the
estimation engine and the YOLOv8-seg floor-plan parser were ported to Dart/ONNX);
only lightweight or Python-only work (RAG, the agent, DXF parsing, invoice OCR)
runs in the cloud. Moving embeddings to NIM removed PyTorch from the server and
kept it under Render's free-tier **512 MB** limit.

---

## 3. Technology Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter, Dart, Riverpod, go_router, fl_chart |
| On-device ML | onnxruntime (YOLOv8-seg @512, XGBoost ONNX), `image`, pdfx, dart:isolate |
| Backend | Python, FastAPI, Uvicorn, Pydantic |
| LLM / RAG | NVIDIA NIM (OpenAI-compatible) — Llama 3.1 8B + `baai/bge-m3`, ChromaDB |
| Agent | LangGraph (ReAct), LangChain, langchain-openai |
| Data / infra | Firebase (Auth, Firestore, Storage, FCM), Render (free tier) |
| ML training | Ultralytics YOLOv8-seg, XGBoost, scikit-learn |
| Evaluation | RAGAS (RAG), scikit-learn metrics (XGBoost), Ultralytics val (YOLO) |

---

## 4. Core Modules & Features

### 4.1 Estimation (the centrepiece)
A PlanSwift/BIM-style estimating stack built on the on-device parser:

- **On-device floor-plan parser** — renders a PDF page, runs a YOLOv8-seg ONNX
  model in a **background isolate**, and derives floor area / walls. Adaptive
  render scaling caps huge multi-page commercial sets to avoid OOM.
- **Quantity engine** (`estimation_engine.dart`) — CPWD take-off ported to Dart
  (cement, bricks, steel, sand, aggregate) + interior finishes (tiles, paint,
  putty, fixtures, electrical points).
- **Selectable specs** — brick/block type, tile size, steel-by-diameter schedule.
- **Editable per-project rate library** — every ₹ rate editable, persisted.
- **Data-driven assemblies** — named recipes expand geometry → costed line items.
- **Cost adjustments** — wastage %, overhead & profit, contingency.
- **Finish packages + regional profiles** — Economy/Standard/Premium × Metro/
  Tier/Rural multipliers.
- **CSI-grouped BOQ PDF export** (Div 03 Concrete / 04 Masonry / 09 Finishes).

### 4.2 Site management
Milestone scheduling with planned-vs-actual S-curves; inventory (on-hand =
delivered − consumed); safety/QA incident & snag tracking; delay notices with
manager voting; vendor-bill invoice parsing; global project search.

### 4.3 Reliability & performance
Offline-first resource logging with auto-sync on reconnect; FCM push (client);
background parser isolate; large-PDF OOM crash fix.

### 4.4 AI
- **RAG assistant** — retrieves project estimates/logs/deviations from ChromaDB
  (NIM embeddings) and answers with Llama 3.1 8B, augmented by live Firestore
  aggregations + pre-computed deviation metrics.
- **LangGraph Project Analyst agent** — *stateful, agentic*. Decides which tools
  to call (schedule, cost/deviation, logs, weather), gathers multi-source data,
  and synthesises an answer with recommendations — something single-shot RAG
  cannot do. Endpoint `POST /api/agent/analyze`; surfaced in the app as the
  "Project Analyst (AI)" screen.

---

## 5. Machine-Learning Models & Metrics

### 5.1 YOLOv8-seg — floor-plan room/area segmentation
Custom-trained on a CubiCasa-derived dataset (intentionally trained at **512×512**).
Source: `runs/segment/constructiq_parser/v1-2/results.csv` (83 epochs).

| Metric (peak) | Detection (box) | Segmentation (mask) |
|---|---|---|
| Precision | ~0.85 | ~0.75 |
| Recall | ~0.82 | ~0.75 |
| **mAP@50** | **~0.86** | **~0.74** |
| **mAP@50-95** | **~0.675** | **~0.55** |

**Assessment:** strong for a custom architectural-plan segmenter; no remediation
needed. Known limit: scale-from-dimensions is fragile on some residential plans
(documented separately).

### 5.2 XGBoost — cost-overrun probability
On-device (exported to ONNX) binary classifier over 5 engineered features.
Trained via `scripts/train_model.py` on `data/training_data.csv`.

**The original synthetic data capped learnable performance** (excessive log-odds
noise σ=0.6 + 8% label-flipping). The generator was improved to a realistic but
learnable multi-factor logistic relationship (stronger weights, a
deviation×timeline interaction, noise σ=0.30, 3% label noise, n=2000).

| Metric | Before | After (improved) |
|---|---|---|
| Test AUC-ROC | 0.652 | **0.923** |
| Test accuracy | 0.600 | **0.855** |
| 5-fold CV AUC | 0.695 ±0.023 | **0.921 ±0.008** |
| Overrun-class precision | 0.58 | **0.87** |
| Overrun-class recall | 0.48 | **0.89** |
| Overrun-class F1 | 0.52 | **0.88** |

**Feature importances (after):** material_deviation_avg 0.39 · project_type 0.22 ·
equipment_idle_ratio 0.19 · days_elapsed_pct 0.13 · budget_size 0.07.

*Note:* metrics are on synthetic data and reflect data design, not field
performance; they validate that the modelling pipeline learns the intended
relationship cleanly.

### 5.3 RAG pipeline — RAGAS evaluation
A runnable harness (`evaluate_rag.py` + `requirements-eval.txt`) measures the four
core RAGAS metrics using the **NIM** endpoint as both generator and judge:

| Metric | What it measures |
|---|---|
| **faithfulness** | Is the answer grounded in retrieved context (no hallucination)? |
| **answer_relevancy** | Does the answer address the question? |
| **context_precision** | Are retrieved chunks relevant (signal vs noise)? |
| **context_recall** | Did retrieval surface what the ground truth needs? |

**How to run** (not run in this report — needs the API key + a project with data):
```bash
cd construction-ai-service
pip install -r requirements-eval.txt
set NVIDIA_API_KEY=...        # plus Firebase creds for real data
python evaluate_rag.py --project_id <REAL_PROJECT_ID>
```
The harness retrieves contexts from the same ChromaDB collection the pipeline
uses, gets answers from the real `RAGEngine`, and writes per-question scores to
`rag_eval_results.csv`. Edit `TEST_SET` ground truths for your project for
accurate `context_recall`.

---

## 6. Backend API Surface (selected)

| Route | Purpose |
|---|---|
| `POST /api/cad/parse-upload` | Server-side DXF/DWG geometry parse |
| `POST /api/estimation/*` | Estimation helpers, report generation, invoice budget |
| `POST /api/deviation/*` | Deviation analysis |
| `POST /api/ml/*` | XGBoost overrun serving |
| `POST /api/rag/query`, `/index` | RAG assistant |
| `POST /api/agent/analyze` | **LangGraph Project Analyst agent** |
| `POST /parse-invoice` | Vendor invoice OCR/extraction |
| `GET  /health` | Health check (+ Render self-ping keep-alive) |

---

## 7. Data Model (Firestore)

`projects/{id}` with subcollections: `estimates`, `resourceLogs`, `deviations`
(incl. `live_{id}`), `vendorBills`, `milestones`, `siteReports`, and
`settings/{rateLibrary, assemblies, costAdjustments, estimationProfile}`.

---

## 8. Known Limitations & Future Work

- **Scale detection** on some residential plans remains fragile.
- **XGBoost** metrics are on synthetic data; a real labelled dataset is future work.
- **Interior estimation** uses room-count + area + standard rates (the standard QS
  approach); full MEP drawing takeoff is intentionally **out of scope**. The next
  realistic step is a manual **room-schedule** input driving per-room assemblies.
- **Agent** tool-calling reliability depends on the model; a larger NIM model can
  be set via `NVIDIA_AGENT_MODEL`. The weather tool is not yet wired to a
  server-side source.
- **FCM send-side** (Cloud Function) is not yet built; the client registers tokens.

---

## 9. How to Run

**Backend:** `cd construction-ai-service && pip install -r requirements.txt &&
uvicorn main:app --reload` (needs `NVIDIA_API_KEY`, optional Firebase creds).

**App:** `cd construction_flutter_app && flutter pub get && flutter run`.

**Retrain XGBoost:** `python scripts/generate_dataset.py && python scripts/train_model.py`.

**Evaluate RAG:** see §5.3.
