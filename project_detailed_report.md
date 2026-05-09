# ConstructIQ: Detailed Project Report

## 1. Project Overview
**ConstructIQ** is a comprehensive, AI-powered full-stack platform designed to bridge the gap between architectural planning and on-site construction execution. Built as a Final Year B.Tech CSE Major Project at MIET (Autonomous), Jammu, the platform leverages Artificial Intelligence, Machine Learning, and real-time data to automate quantity takeoffs, detect resource wastage, predict project delays, and provide intelligent site management.

**Team Members:** Sukhshum Vaishnavi, Karan Sharma, Mohit Koul
**Batch:** 2022–2026

## 2. System Architecture
The system is built on a modern, decoupled microservices architecture:
*   **Mobile Frontend:** Built with Flutter, providing a cross-platform (Android/iOS) mobile application with a "Digital Foreman" aesthetic.
*   **Backend Infrastructure:** Google Firebase provides Authentication, Cloud Firestore (NoSQL real-time database), and Cloud Storage (for media and PDFs).
*   **AI/ML Microservice:** A Python FastAPI backend handles complex tasks like CAD parsing, ML inference, and RAG-based AI interactions.
*   **AI Engines:** Integrates NVIDIA NIM (Llama 3.1) for conversational AI and reasoning, alongside custom Machine Learning models (XGBoost).
*   **Vector Database:** ChromaDB is used to store and query vectorized project data for Retrieval-Augmented Generation (RAG).

## 3. User Roles & Permissions
The system enforces strict role-based access control (RBAC):
*   **Admin:** Has root access to manage users, create projects, upload CAD files, and allocate teams.
*   **Manager:** Accesses high-level dashboard views, approves vendor bills, monitors key performance indicators (KPIs), handles delay notices, and views AI-generated analytical reports.
*   **Site Engineer:** The primary on-site user. Responsible for daily resource logging, managing the workforce, capturing photo evidence, and logging delays.
*   **Project Owner:** Has view-only access to monitor project progress, budget status, and team transparency without operational capabilities.

## 4. AI Backend Service (Python FastAPI)
The AI microservice (`construction-ai-service`) is the intelligence core of ConstructIQ, exposing modular APIs for various tasks:

### 4.1 CAD Parser (`cad_parser.py`)
The CAD parser is a highly complex module responsible for extracting physical dimensions and structural elements from `.DXF` files. It translates raw vector geometry into civil engineering metrics. 

**Evolution & Resolution of Inaccuracies:**
Initially, the parser suffered from massive deviation errors (e.g., calculating 624 m² for a 171 m² footprint) due to several fundamental challenges inherent in architectural CAD files:
1.  **Side-by-Side Floor Plan Collisions:** Architects frequently draw multiple floors (e.g., Ground Floor and First Floor) next to each other on the same 2D plane. The original algorithm relied on an overall geometric "bounding box," which mistakenly calculated the entire drawn space (including the empty space between the drawings) as one giant single-story building.
2.  **Generic Layering Guesses:** Early iterations relied on loose substring matching for layers. "Room 1" text was sometimes confused as "Level 1," causing artificial area multipliers.
3.  **Missing Multi-Story Awareness:** The parser failed to recognize multi-floor designations hidden within complex CAD Blocks, resulting in area calculations defaulting to a single floor.

**The Optimization Architecture:**
To achieve sub-2% error margins, the parser was completely restructured from a reactive heuristic script into a **Confidence-Based Geometry Reconstruction Engine**:
*   **Dominant Cluster Isolation (DBSCAN):** To permanently solve the side-by-side collision issue, the parser now uses the `DBSCAN` machine learning algorithm to group all entities by spatial proximity. It isolates the "dominant" structural cluster and ignores all detached side-by-side elements, ensuring calculations only apply to a single floor footprint.
*   **Graph-Based Wall Loop Reconstruction:** The engine extracts all structural wall lines, snaps their endpoints to a grid, and builds a planar graph using `networkx`. It then executes cycle basis algorithms to find all closed loops (rooms) and determines the exact outer boundary of the building footprint without relying on bounding box inflation.
*   **Confidence Scoring Engine:** Instead of rigid `if/else` fallbacks, the parser evaluates four independent strategies simultaneously: Outline Polylines, Dimension-Anchored Footprints, Wall Loop Reconstruction, and Text Annotations. Each strategy returns an area and a confidence score (0.0 to 1.0). The engine selects the valid result with the highest confidence.
*   **Sanity Validation Layer:** Results are cross-checked. If a chosen strategy's area drastically deviates (e.g., >2.0x or <0.5x) from highly confident peers, it is rejected, eliminating catastrophic miscalculations.

**Advanced Enhancements:**
*   **Multi-Floor Decoder:** A deep text-parsing engine scans both standard text elements and nested CAD Blocks. It explicitly looks for precise regular expressions like `(GROUND|GF|LEVEL\s*1)` combined with keywords like `FLOOR` or `PLAN`. Once it identifies that the drawing represents multiple distinct levels, it applies this as a multiplier to the single footprint derived from Strategy 2.
*   **Automated Opening Deductions:** The parser counts door and window entities (via strict layer mappings like `DOOR_RULES` and `WINDOW_RULES`). It assigns standard CPWD areas (e.g., 1.89 m² per door) and automatically subtracts this "empty space" from the gross wall area, ensuring material takeoffs (like bricks and plaster) are only calculated for solid structures.
*   **Output:** Generates a highly accurate, structured JSON representation of the building's geometry (total net wall length, total floor area multiplied by floor count, concrete volume, and structural counts).

### 4.2 Estimation Engine (`estimation_engine.py`)
*   **Functionality:** Performs Automated Quantity Takeoffs (QTO) based on the geometry extracted by the CAD parser.
*   **Formulas:** Utilizes standard Civil Engineering formulas based on CPWD (Central Public Works Department) norms.
*   **Material Calculation:** Calculates required quantities for structural materials (Cement, Bricks, Steel, Sand, Aggregate), deducting areas for openings like doors and windows.
*   **Labour Estimation:** Predicts the required labour-days per trade (Mason, Labourer, Steel Fixer, Plasterer) based on CPWD productivity benchmarks.

### 4.3 Machine Learning Engine (`ml_predictor.py` & `deviation_analysis.py`)
*   **Deviation Analysis:** Compares the estimated material quantities against the actual consumed materials reported in daily logs. It calculates percentage deviations and z-scores to flag critical overruns.
*   **Cost Overrun Prediction:** An XGBoost model (trained on synthetic construction records) analyzes consumption patterns, equipment idle ratios, and budget sizes to predict the probability of a project exceeding its budget or timeline.

### 4.4 RAG AI Assistant (`rag_engine.py`)
*   **Functionality:** Provides a specialized "Project AI" chatbot for engineers and managers.
*   **Data Indexing:** Indexes project estimates, recent daily logs, vendor bills, and deviation reports into a local ChromaDB instance using SentenceTransformer embeddings.
*   **Inference:** Uses NVIDIA NIM (Llama 3.1 8B Instruct) to answer site-specific queries (e.g., "How much cement was used last week?") by retrieving relevant context from the vector database.
*   **Geometry Validation:** The LLM is also used as a fallback to validate whether extracted CAD dimensions are physically plausible for residential construction.

### 4.5 Invoice Parsing (`invoice_parser.py`)
*   **Functionality:** Automates data entry by extracting structured data from uploaded vendor bills (PDFs or images).
*   **Extraction Pipeline:** 
    1. Attempts text extraction using `pdfplumber`.
    2. Falls back to OCR (`pytesseract`) for scanned documents.
    3. Uses NVIDIA NIM AI to extract a structured JSON schema containing vendor name, invoice number, line items (material, quantity, rate), and grand total.
    4. Has a Regex fallback if the AI extraction fails.

## 5. Mobile Application (Flutter)
The frontend (`construction_flutter_app`) is designed for ease of use in the field, featuring a "Digital Foreman" design system with semantic colors (Command Blue, Amber, Red).

### 5.1 App Navigation & Routing (`app_router.dart`)
*   Utilizes `go_router` for declarative routing and deep linking.
*   Implements role-based redirection, ensuring users are routed to their specific shell (e.g., `ManagerDashboard`, `EngineerHome`, `OwnerDashboard`) upon login.

### 5.2 Core Features
*   **Dashboards:** Tailored dashboards for each role, displaying critical metrics, recent logs, active delays, and project health meters.
*   **Project Management:** Screens to create projects, view details, upload CAD files, and manage team allocations.
*   **Daily Logging (`log_entry_screen.dart`):** Site engineers log daily material usage and workforce attendance. Submissions require photo evidence and capture precise GPS coordinates to prevent spoofing.
*   **Weather-Aware Systems:** Integrates with the Open-Meteo API. If adverse weather is detected at the site coordinates, the app locks specific logging fields (e.g., preventing concrete pouring logs during heavy rain).
*   **Finance & Billing (`bill_upload_screen.dart`):** Allows users to upload vendor bills. Integrates with the backend invoice parser to auto-fill material delivery records.
*   **Delay Management:** A collaborative workflow where engineers report delays. Notices require peer consensus before escalating to managers, who can then adjust the project timeline.
*   **AI Chat Interface:** A dedicated chat screen interfacing with the RAG engine for on-the-fly project intelligence.
*   **Reports & Analytics:** Managers can view detailed reports, ML-predicted risk scores, and efficiency metrics, with the ability to generate and preview PDF reports.

## 6. Data Models & Database Structure
The application relies on Cloud Firestore with a well-structured document model:
*   `users`: Stores user profiles, roles, and contact info.
*   `projects`: Stores core project details (budget, dates, location, status, CAD data).
    *   *Sub-collections:*
        *   `estimates`: Stores the CPWD-generated material and labour estimates.
        *   `resourceLogs`: Daily submissions from site engineers.
        *   `vendorBills`: Extracted data from uploaded invoices.
        *   `deviations`: Records of critical material overruns.
        *   `delays`: Tracked delay events and peer consensus notices.

## 7. Data Integrity & Security
*   **Immutable Logs:** Once a daily log is submitted to Firestore, it cannot be edited, preventing the tampering of historical site data.
*   **Geofencing:** GPS coordinates are captured during log submissions to verify the engineer is actually on-site.
*   **Firebase Authentication:** Secures endpoints and manages user identities. Backend APIs verify Firebase ID tokens via a custom middleware (`auth_middleware.py`) to ensure secure communication between the mobile app and the AI service.

---
*Report Generated Automatically via ConstructIQ AI Assistant.*
