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
                    logs = self.db.collection("projects").document(project_id).collection("resourceLogs").order_by("date", direction=firestore.Query.DESCENDING).limit(5).get()
                    
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

                    base_context = (
                        f"[CRITICAL LIVE CONTEXT SETTINGS - ALWAYS TRUE RIGHT NOW]\n"
                        f"Project Name: {p.get('name')}\n"
                        f"Status: {p.get('status')}\n"
                        f"User's Planned/Target Budget: ₹{p.get('plannedBudget', 0)}\n"
                        f"CAD Estimated Material Budget: ₹{est_cost:,.2f}  (Use this if user asks for 'estimated budget' or 'budget' and Planned is 0)\n"
                        f"Total Spent/Invoiced To Date: ₹{inv_total:,.2f}\n"
                        f"Recent Logs (Consumption): {recent_logs}\n"
                        f"========================================================\n\n"
                    )
        except Exception as e:
            print(f"Failed to fetch live project metadata: {e}")

        try:
            collection = self.db_manager.client.get_or_create_collection(
                name=f"project_{project_id}",
                embedding_function=self.db_manager.embedding_fn
            )
            results = collection.query(query_texts=[question], n_results=10)
            context = base_context + "\n".join(results['documents'][0])
        except Exception:
            context = base_context + "No specific project data indexed yet in the vector database."

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
