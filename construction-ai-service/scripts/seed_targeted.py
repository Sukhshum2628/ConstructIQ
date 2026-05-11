"""
ConstructIQ — Targeted Project Seeder
=====================================
Seeds specific existing projects with demo data (logs, invoices, deviations).
Usage: python scripts/seed_targeted.py <project_id1> <project_id2> ...
"""

import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta
import random
import os
import sys

# -- Firebase Init --
service_account_path = os.path.join(os.path.dirname(__file__), '..', 'service_account.json')
if not firebase_admin._apps:
    cred = credentials.Certificate(service_account_path)
    firebase_admin.initialize_app(cred)

db = firestore.client()

# -- Constants --
DEMO_USER_UID = 'VC3G0ZmK6cTpYt7SUmcmvopF7F72'
TODAY = datetime.now()

def ts(dt):
    return dt

def seed_logs(project_id):
    print(f"  Seeding resource logs for {project_id}...")
    notes_options = [
        'Brickwork in progress on 2nd floor.',
        'Column casting completed for section B.',
        'Plastering ongoing on ground floor walls.',
        'Shuttering removed from 1st floor slab.',
        'Electrical conduit laying in progress.',
    ]
    
    for day_offset in range(15):
        log_date = TODAY - timedelta(days=day_offset)
        if log_date.weekday() == 6: continue
        
        log_data = {
            'projectId': project_id,
            'loggedBy': 'user_engineer_mohit',
            'date': ts(log_date),
            'materialUsage': {
                'cement': round(random.uniform(20, 50), 1),
                'sand': round(random.uniform(2, 8), 1),
                'bricks': random.randint(1000, 3000),
                'aggregate': round(random.uniform(2, 6), 1),
            },
            'laborHours': round(random.uniform(160, 300), 1),
            'notes': random.choice(notes_options),
            'weatherCondition': random.choice(['Sunny', 'Cloudy', 'Clear']),
            'createdAt': ts(log_date),
        }
        db.collection('projects').document(project_id).collection('resourceLogs').add(log_data)

def seed_bills(project_id):
    print(f"  Seeding vendor bills for {project_id}...")
    vendors = [('Jammu Cement Co.', 150000), ('Sharma Sand', 45000), ('NK Steel Traders', 280000)]
    for name, amount in vendors:
        bill_date = TODAY - timedelta(days=random.randint(5, 30))
        bill = {
            'projectId': project_id,
            'vendorName': name,
            'amount': float(amount),
            'date': ts(bill_date),
            'category': 'Materials',
            'uploadedBy': 'user_manager_karan',
            'createdAt': ts(bill_date),
        }
        db.collection('projects').document(project_id).collection('vendorBills').add(bill)

def seed_deviations(project_id):
    print(f"  Seeding deviations for {project_id}...")
    dev = {
        'projectId': project_id,
        'deviationPct': 14.5,
        'zScore': 2.1,
        'flagged': True,
        'overallSeverity': 'warning',
        'aiInsightSummary': 'Cement consumption 14.5% above plan. High variance detected.',
        'generatedAt': ts(TODAY - timedelta(days=1)),
        'createdAt': ts(TODAY - timedelta(days=1)),
    }
    db.collection('projects').document(project_id).collection('deviations').add(dev)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python scripts/seed_targeted.py <project_id1> <project_id2> ...")
        sys.exit(1)
        
    pids = sys.argv[1:]
    print(f"Targeting projects: {pids}")
    
    for pid in pids:
        seed_logs(pid)
        seed_bills(pid)
        seed_deviations(pid)
        
    print("\n✅ Targeted seeding complete.")
