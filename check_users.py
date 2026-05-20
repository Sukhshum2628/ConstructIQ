import firebase_admin
from firebase_admin import credentials, firestore

try:
    cred = credentials.Certificate("construction-ai-service/service_account.json")
    firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"Error initializing Firebase: {e}")
    exit(1)

db = firestore.client()

print("Fetching all users from Firestore...")
users_ref = db.collection("users")
docs = users_ref.stream()

found = False
for doc in docs:
    found = True
    print(f"UID: {doc.id}")
    data = doc.to_dict()
    for k, v in data.items():
        print(f"  {k}: {v}")
    print("-" * 30)

if not found:
    print("No users found in the 'users' collection.")
