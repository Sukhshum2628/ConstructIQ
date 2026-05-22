import firebase_admin
from firebase_admin import credentials, firestore

try:
    cred = credentials.Certificate("construction-ai-service/service_account.json")
    firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"Error initializing Firebase: {e}")
    exit(1)

db = firestore.client()

uids = [
    '8fpCTaXTuKXpX349GGjt1DHQuPB3', # KaranENG
    'KP8zBoY7DyTy43grL0fDEV9gnS12', # Karan Eng
    'kVAawiRK00XQpKjXUfuAQGyXIHz1', # Sukhshum
]

print("Starting Firestore site engineer migration for resource logs...")

projects_ref = db.collection("projects")
projects = list(projects_ref.stream())

total_updated = 0
total_checked = 0

for project_doc in projects:
    project_id = project_doc.id
    project_data = project_doc.to_dict()
    project_name = project_data.get("name", project_id)
    
    print(f"\nChecking logs for project: {project_name} ({project_id})...")
    
    logs_ref = db.collection("projects").document(project_id).collection("resourceLogs")
    logs = list(logs_ref.stream())
    
    for log_doc in logs:
        total_checked += 1
        log_id = log_doc.id
        log_data = log_doc.to_dict()
        
        logged_by = log_data.get("loggedBy", "")
        
        # Check if the field is "seeded", empty, or "Unknown"
        if logged_by == "seeded" or not logged_by or logged_by == "Unknown":
            # Deterministic hash of log ID
            hash_val = sum(ord(char) for char in log_id)
            assigned_uid = uids[hash_val % 3]
            
            print(f"  - Migrating log {log_id}: '{logged_by}' -> '{assigned_uid}'")
            log_doc.reference.update({"loggedBy": assigned_uid})
            total_updated += 1

print(f"\nMigration complete. Checked {total_checked} logs. Updated {total_updated} logs to real site engineer UIDs.")
