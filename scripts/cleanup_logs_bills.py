import sys
import os
import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase Admin
try:
    cred = credentials.Certificate("construction-ai-service/service_account.json")
    firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"Error initializing Firebase: {e}")
    exit(1)

db = firestore.client()

PROJECT_IDS = [
    "0c78434d-9dc5-468a-802f-5db27c4fe0c9",
    "0fb34ddd-6898-4aa2-aa7f-ab93b51d46c3",
    "3cdf0520-0dda-4666-b67b-2f8059a7a71a",
    "d1a6cf6e-0585-4b25-81eb-77ee8a9e37cf",
    "d47b318e-15de-4332-9316-f5a77c651896",
    "dc213e61-4bf9-4f9f-97ae-37f63cea1ce5",
    "e20cead9-d543-4dde-a81a-2c6dc91c4cd0",
    "fd9d20fd-8441-4bb1-be93-4f17cb93dd7f",
]

total_logs_deleted = 0
total_bills_deleted = 0

print("Starting cleanup of resourceLogs and vendorBills...")

for pid in PROJECT_IDS:
    # 1. Clean resourceLogs subcollection
    logs_ref = db.collection("projects").document(pid).collection("resourceLogs")
    logs = list(logs_ref.stream())
    logs_deleted = 0
    for log in logs:
        log.reference.delete()
        logs_deleted += 1
    total_logs_deleted += logs_deleted
    
    # 2. Clean vendorBills subcollection
    bills_ref = db.collection("projects").document(pid).collection("vendorBills")
    bills = list(bills_ref.stream())
    bills_deleted = 0
    for bill in bills:
        bill.reference.delete()
        bills_deleted += 1
    total_bills_deleted += bills_deleted
    
    print(f"Project {pid}: Deleted {logs_deleted} logs, {bills_deleted} bills.")

print("\nCleanup completed.")
print(f"Deleted {total_logs_deleted} resourceLogs and {total_bills_deleted} vendorBills across 8 projects")
