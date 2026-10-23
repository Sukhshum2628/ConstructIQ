import firebase_admin
from firebase_admin import auth, credentials
from fastapi import Request, HTTPException
import os
import json

# Determine execution environment (default to production if unset — never default to permissive)
ENV = os.getenv("ENV", "production").lower()
USE_MOCK_AUTH = False

try:
    if not firebase_admin._apps:
        # 1. Try JSON string from environment (Railway/Render/Production)
        firebase_credentials_json = os.getenv('FIREBASE_CREDENTIALS_JSON')
        if firebase_credentials_json:
            cred_dict = json.loads(firebase_credentials_json)
            cred = credentials.Certificate(cred_dict)
            firebase_admin.initialize_app(cred)
            print("Firebase Admin initialized via FIREBASE_CREDENTIALS_JSON (ENV).")
        else:
            # 2. Try local file (Development)
            cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "service_account.json")
            if os.path.exists(cred_path):
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
                print(f"Firebase Admin initialized via {cred_path} (FILE).")
            else:
                if ENV == "local":
                    USE_MOCK_AUTH = True
                    print("ENV=local: Firebase credentials not found. Enabled MOCK auth for local dev.")
                else:
                    raise RuntimeError(
                        f"Firebase credentials not found and ENV='{ENV}'. "
                        "Refusing to start in insecure mock mode. Set FIREBASE_CREDENTIALS_JSON or ENV=local."
                    )
except Exception as e:
    if ENV == "local":
        USE_MOCK_AUTH = True
        print(f"Auth initialization warning in local dev: {e}. Falling back to MOCK mode.")
    else:
        # Fail the deployment / startup in production
        raise RuntimeError(f"FATAL: Firebase Admin initialization failed in {ENV} environment: {e}") from e

async def verify_firebase_token(request: Request):
    if USE_MOCK_AUTH:
        # Return a mock user for local demo stability
        return {"uid": "demo-user-123", "email": "demo@constructiq.ai"}

    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing authorization header")
    
    token = auth_header.split(" ")[1]
    try:
        decoded_token = auth.verify_id_token(token)
        return decoded_token
    except Exception as e:
        raise HTTPException(status_code=401, detail=f"Invalid token: {str(e)}")


async def check_project_membership(uid: str, project_id: str):
    """
    Verify if a user has access to a project (IDOR guard).
    Checks teamMembers and owner fields in Firestore /projects/{project_id}.
    In mock auth mode, demo-user-123 is allowed for local dev.
    """
    if USE_MOCK_AUTH and uid == "demo-user-123":
        return True

    try:
        from modules.rag_engine import rag_engine
        db = rag_engine.db
        if db == "MOCK" or db is None:
            # If database client is in mock mode (e.g. testing)
            return True

        project_ref = db.collection("projects").document(project_id)
        doc = project_ref.get()
        if not doc.exists:
            raise HTTPException(status_code=404, detail="Project not found.")

        data = doc.to_dict() or {}
        team_members = data.get("teamMembers", [])
        owner_id = data.get("ownerUserId") or data.get("userId")

        if uid == owner_id or uid in team_members:
            return True

        # Also check /users/{uid} -> projectIds list if present
        user_ref = db.collection("users").document(uid)
        user_doc = user_ref.get()
        if user_doc.exists:
            user_data = user_doc.to_dict() or {}
            project_ids = user_data.get("projectIds", [])
            if project_id in project_ids:
                return True

        raise HTTPException(status_code=403, detail="Forbidden: User is not a member of this project.")
    except HTTPException:
        raise
    except Exception as e:
        # Avoid leaking internal DB exceptions, re-raise HTTP 403/500
        raise HTTPException(status_code=403, detail="Forbidden: Project access validation failed.")
