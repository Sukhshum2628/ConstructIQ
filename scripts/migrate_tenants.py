import os
import sys
import firebase_admin
from firebase_admin import credentials, firestore

def main():
    service_account_path = "construction-ai-service/service_account.json"
    if not os.path.exists(service_account_path):
        # Fallback to root or look up
        if os.path.exists("../construction-ai-service/service_account.json"):
            service_account_path = "../construction-ai-service/service_account.json"
        else:
            print(f"Service account file not found at {service_account_path}")
            sys.exit(1)

    try:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Error initializing Firebase: {e}")
        sys.exit(1)

    db = firestore.client()
    default_company_id = "default_constructiq_company"

    print("=== Step 1: Create or Verify Default Company ===")
    company_ref = db.collection("companies").document(default_company_id)
    company_doc = company_ref.get()
    if not company_doc.exists:
        company_ref.set({
            "name": "ConstructIQ Enterprise Default",
            "createdAt": firestore.SERVER_TIMESTAMP,
            "createdBy": "system_migration",
            "isActive": True
        })
        print(f"Created default company document: /companies/{default_company_id}")
    else:
        print(f"Default company already exists: /companies/{default_company_id}")

    print("\n=== Step 2: Migrate Projects Collection ===")
    projects = db.collection("projects").stream()
    projects_migrated = 0
    projects_already_set = 0
    for doc in projects:
        data = doc.to_dict() or {}
        if not data.get("companyId"):
            db.collection("projects").document(doc.id).update({
                "companyId": default_company_id
            })
            projects_migrated += 1
            print(f"  Updated project {doc.id} ('{data.get('name', 'Unknown')}') -> companyId: {default_company_id}")
        else:
            projects_already_set += 1

    print(f"Projects checked. Migrated: {projects_migrated}, Already had companyId: {projects_already_set}")

    print("\n=== Step 3: Migrate Users Collection ===")
    users = db.collection("users").stream()
    users_migrated = 0
    users_already_set = 0
    for doc in users:
        data = doc.to_dict() or {}
        if not data.get("companyId"):
            db.collection("users").document(doc.id).update({
                "companyId": default_company_id
            })
            users_migrated += 1
            print(f"  Updated user {doc.id} ('{data.get('name', 'Unknown')}') -> companyId: {default_company_id}")
        else:
            users_already_set += 1

    print(f"Users checked. Migrated: {users_migrated}, Already had companyId: {users_already_set}")

    print("\n=== Step 4: Migrate Workforce Collection ===")
    workforce = db.collection("workforce").stream()
    workforce_migrated = 0
    workforce_already_set = 0
    for doc in workforce:
        data = doc.to_dict() or {}
        if not data.get("companyId"):
            db.collection("workforce").document(doc.id).update({
                "companyId": default_company_id
            })
            workforce_migrated += 1
            print(f"  Updated worker {doc.id} ('{data.get('name', 'Unknown')}') -> companyId: {default_company_id}")
        else:
            workforce_already_set += 1

    print(f"Workforce checked. Migrated: {workforce_migrated}, Already had companyId: {workforce_already_set}")

    print("\n=== Phase 0 Migration Complete! ===")

if __name__ == "__main__":
    main()
