import os
import sys
import firebase_admin
from firebase_admin import credentials, firestore

def test_tenant_isolation():
    service_account_path = "construction-ai-service/service_account.json"
    if not os.path.exists(service_account_path):
        if os.path.exists("../construction-ai-service/service_account.json"):
            service_account_path = "../construction-ai-service/service_account.json"
        else:
            print(f"Service account file not found at {service_account_path}")
            sys.exit(1)

    try:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
    except Exception as e:
        print(f"Firebase already initialized or error: {e}")

    db = firestore.client()

    print("\n--- Test 1: Verify Default Company Exists ---")
    company_doc = db.collection("companies").document("default_constructiq_company").get()
    assert company_doc.exists, "Default company document missing!"
    print("PASS: Default company document exists.")

    print("\n--- Test 2: Check All Projects Have companyId ---")
    projects = list(db.collection("projects").stream())
    for p in projects:
        data = p.to_dict() or {}
        assert "companyId" in data and len(data["companyId"]) > 0, f"Project {p.id} missing companyId!"
    print(f"PASS: All {len(projects)} projects have valid companyId.")

    print("\n--- Test 3: Check All Users Have companyId ---")
    users = list(db.collection("users").stream())
    for u in users:
        data = u.to_dict() or {}
        assert "companyId" in data and len(data["companyId"]) > 0, f"User {u.id} missing companyId!"
    print(f"PASS: All {len(users)} users have valid companyId.")

    print("\n--- Test 4: Verify Multi-Tenant Query Isolation ---")
    # Simulate Company A and Company B
    comp_a_id = "test_co_a_" + os.urandom(4).hex()
    comp_b_id = "test_co_b_" + os.urandom(4).hex()

    # Create dummy projects for Company A and B
    p_a_ref = db.collection("projects").document(f"proj_{comp_a_id}")
    p_b_ref = db.collection("projects").document(f"proj_{comp_b_id}")

    p_a_ref.set({"name": "Project Alpha Co A", "companyId": comp_a_id})
    p_b_ref.set({"name": "Project Beta Co B", "companyId": comp_b_id})

    # Query Company A projects
    comp_a_projects = [
        d.to_dict()["name"] for d in db.collection("projects").where("companyId", "==", comp_a_id).stream()
    ]
    assert "Project Alpha Co A" in comp_a_projects
    assert "Project Beta Co B" not in comp_a_projects, "Data leak! Company B project visible to Company A"
    print(f"PASS: Company A sees only {comp_a_projects}")

    # Query Company B projects
    comp_b_projects = [
        d.to_dict()["name"] for d in db.collection("projects").where("companyId", "==", comp_b_id).stream()
    ]
    assert "Project Beta Co B" in comp_b_projects
    assert "Project Alpha Co A" not in comp_b_projects, "Data leak! Company A project visible to Company B"
    print(f"PASS: Company B sees only {comp_b_projects}")

    # Cleanup test projects
    p_a_ref.delete()
    p_b_ref.delete()
    print("PASS: Test projects cleaned up.")

    print("\n==========================================")
    print("ALL TENANT ISOLATION TESTS PASSED SUCCESSFULLY!")
    print("==========================================")

if __name__ == "__main__":
    test_tenant_isolation()
