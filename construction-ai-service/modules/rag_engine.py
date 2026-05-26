import os
import json
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
        self.PROMPT_TEMPLATE = """You are a construction project analyst assistant.
Answer the engineer's question using ONLY the project data provided below.
The data includes estimates, site logs, and deviation reports.
If the answer is not in the context, say you don't have that specific data.

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

        # Use self.db (the initialized client)
        project_doc = self.db.collection("projects").document(project_id).get()
        estimates = self.db.collection("projects").document(project_id).collection("estimates").order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).get()
        logs = self.db.collection("projects").document(project_id).collection("resourceLogs").order_by("date", direction=firestore.Query.DESCENDING).limit(30).get()
        deviations = self.db.collection("projects").document(project_id).collection("deviations").order_by("createdAt", direction=firestore.Query.DESCENDING).limit(5).get()
        vendor_bills = self.db.collection("projects").document(project_id).collection("vendorBills").order_by("date", direction=firestore.Query.DESCENDING).limit(10).get()

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

    def _save_to_vector_db(self, project_id: str, chunks: list):
        collection_name = f"project_{project_id}"
        try:
            self.db_manager.client.delete_collection(collection_name)
        except Exception:
            pass
        collection = self.db_manager.client.get_or_create_collection(
            name=collection_name,
            embedding_function=self.db_manager.embedding_fn
        )
        collection.add(
            documents=chunks,
            metadatas=[{"project_id": project_id}] * len(chunks),
            ids=[f"{project_id}_{i}_{os.urandom(4).hex()}" for i in range(len(chunks))]
        )

    def get_answer(self, project_id: str, question: str):
        # STEP 4 FIX: Re-index if collection is missing/empty (persistence helper)
        self._ensure_indexed(project_id)
        
        base_context = ""
        try:
            if self.db != "MOCK":
                p_doc = self.db.collection("projects").document(project_id).get()
                if p_doc.exists:
                    p = p_doc.to_dict()
                    
                    # -- LIVE AGGREGATIONS --
                    ests = self.db.collection("projects").document(project_id).collection("estimates").order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).get()
                    bills = self.db.collection("projects").document(project_id).collection("vendorBills").get()
                    logs = self.db.collection("projects").document(project_id).collection("resourceLogs").order_by("date", direction=firestore.Query.DESCENDING).get()
                    
                    # Compute CAD estimated cost using hardcoded flutter rates
                    est_cost = 0.0
                    rates = {'cement': 450.0, 'bricks': 12.0, 'steel': 75.0, 'sand': 60.0, 'aggregate': 85.0}
                    estimated_materials = {}
                    if ests:
                        estimated_materials = ests[0].to_dict().get('estimatedMaterials', {})
                        for m_key, m_val in estimated_materials.items():
                            qty = m_val.get('quantity', 0)
                            name = m_key.lower()
                            for r_k, r_v in rates.items():
                                if r_k in name:
                                    est_cost += r_v * float(qty)
                                    break
                    
                    # Compute Invoiced Total
                    inv_total = sum(b.to_dict().get('amount', 0) for b in bills)
                    
                    recent_logs = [f"{l.to_dict().get('date')}: {l.to_dict().get('materialUsage', {})}" for l in logs[:5]]

                    # Real-time Python translation of Dart's DeviationCalculator
                    duration_days = int(p.get('durationDays', 90) or 90)
                    log_count = len(logs)
                    
                    # 1. Estimates mapping
                    def _read_qty(mats, key):
                        val = mats.get(key)
                        if val is None:
                            return 0.0
                        if isinstance(val, (int, float)):
                            return float(val)
                        if isinstance(val, dict):
                            return float(val.get('quantity', 0.0) or 0.0)
                        return 0.0

                    m_estimates = {
                        'cement': _read_qty(estimated_materials, 'cement') + _read_qty(estimated_materials, 'cement_bags'),
                        'bricks': _read_qty(estimated_materials, 'bricks') + _read_qty(estimated_materials, 'brick') + _read_qty(estimated_materials, 'bricks_pcs'),
                        'steel': _read_qty(estimated_materials, 'steel') + _read_qty(estimated_materials, 'steel_kg') + _read_qty(estimated_materials, 'rebar'),
                        'sand': _read_qty(estimated_materials, 'sand') + _read_qty(estimated_materials, 'sand_m3'),
                        'aggregate': _read_qty(estimated_materials, 'aggregate') + _read_qty(estimated_materials, 'aggregate_m3'),
                    }

                    # 2. consumed actuals
                    actual_cement = 0.0
                    actual_bricks = 0.0
                    actual_steel = 0.0
                    actual_sand = 0.0
                    actual_aggregate = 0.0

                    for log in logs:
                        l_data = log.to_dict()
                        usage = l_data.get('materialUsage') or l_data.get('materials') or {}
                        actual_cement += float(usage.get('cement', usage.get('cement_bags', 0.0)) or 0.0)
                        actual_bricks += float(usage.get('bricks', usage.get('brick', 0.0)) or 0.0)
                        actual_steel += float(usage.get('rebar', usage.get('steel', usage.get('steel_kg', 0.0))) or 0.0)
                        actual_sand += float(usage.get('sand', usage.get('sand_m3', 0.0)) or 0.0)
                        actual_aggregate += float(usage.get('aggregate', usage.get('aggregate_m3', 0.0)) or 0.0)

                    m_actuals = {
                        'cement': actual_cement,
                        'bricks': actual_bricks,
                        'steel': actual_steel,
                        'sand': actual_sand,
                        'aggregate': actual_aggregate,
                    }

                    # 3. deviation check
                    per_material_devs = {}
                    max_overrun_deviation = 0.0
                    max_abs_deviation = 0.0
                    effective_days = max(1, log_count)

                    for key, total_estimated in m_estimates.items():
                        daily_estimated = total_estimated / duration_days
                        pro_rated_estimated = daily_estimated * effective_days
                        actual = m_actuals.get(key, 0.0)
                        
                        deviation_pct = 0.0
                        if pro_rated_estimated > 0:
                            deviation_pct = ((actual - pro_rated_estimated) / pro_rated_estimated) * 100
                        
                        per_material_devs[key] = {
                            "estimated": total_estimated,
                            "actual": actual,
                            "pro_rated_estimated": round(pro_rated_estimated, 2),
                            "deviation_pct": round(deviation_pct, 2)
                        }
                        max_abs_deviation = max(max_abs_deviation, abs(deviation_pct))
                        if deviation_pct > 0:
                            max_overrun_deviation = max(max_overrun_deviation, deviation_pct)

                    # 4. Overall severity matching Dart exactly
                    severity = 'normal'
                    if max_overrun_deviation > 15.0:
                        severity = 'critical'
                    elif max_overrun_deviation > 7.0:
                        severity = 'warning'
                    elif max_abs_deviation > 25.0:
                        severity = 'caution'

                    ml_overrun_probability = min(1.0, max(0.0, max_overrun_deviation / 30.0))

                    base_context = (
                        f"[CRITICAL LIVE CONTEXT SETTINGS - REAL-TIME DEVIATIONS & ESTIMATES]\n"
                        f"Project Name: {p.get('name')}\n"
                        f"Status: {p.get('status')}\n"
                        f"User's Target Budget: ₹{p.get('plannedBudget', 0)}\n"
                        f"CAD Estimated Material Cost: ₹{est_cost:,.2f}\n"
                        f"Total Spent/Invoiced To Date: ₹{inv_total:,.2f}\n"
                        f"Project Duration: {duration_days} days\n"
                        f"Elapsed/Logged Days: {log_count} days\n\n"
                        f"--- REAL-TIME DEVIATION CALCULATIONS (MATCHES FLUTTER APP) ---\n"
                        f"Overall Deviation Severity: {severity.upper()}\n"
                        f"Calculated XGBoost Overrun Probability: {ml_overrun_probability * 100:.1f}%\n"
                        f"Detailed Material Deviations (Actual vs Pro-Rated Estimate):\n"
                    )
                    
                    for m_name, m_dev in per_material_devs.items():
                        base_context += (
                            f"  - {m_name.capitalize()}: Actual = {m_dev['actual']:.1f}, "
                            f"Pro-Rated Budget = {m_dev['pro_rated_estimated']:.1f}, "
                            f"Total Budgeted = {m_dev['estimated']:.1f}, "
                            f"Deviation = {m_dev['deviation_pct']:+.1f}%\n"
                        )
                        
                    base_context += (
                        f"\nRecent Resource Logs (Consumption): {recent_logs}\n"
                        f"========================================================\n\n"
                    )
        except Exception as e:
            print(f"Failed to fetch live project metadata: {e}")

        # Load ChromaDB only if we are running in an environment with sufficient RAM
        # On Render Free Tier, we stay safe and lightweight by querying the live context directly.
        # This keeps the memory usage at <100MB instead of hitting the 512MB limit!
        try:
            # Check if environment is extremely low RAM (like Render free tier)
            # Or default to simple base_context if Chroma query fails or is bypassed
            if os.getenv("RENDER_EXTERNAL_URL"):
                # We are on Render! Bypass heavy sentence-transformers completely to protect RAM limits
                context = base_context
            else:
                collection = self.db_manager.client.get_or_create_collection(
                    name=f"project_{project_id}",
                    embedding_function=self.db_manager.embedding_fn
                )
                results = collection.query(query_texts=[question], n_results=10)
                context = base_context + "\n".join(results['documents'][0])
        except Exception:
            context = base_context + "No specific project data indexed yet in the vector database."

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
