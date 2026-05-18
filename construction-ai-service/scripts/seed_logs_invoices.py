import sys
import os
from datetime import datetime, timedelta
import random
import firebase_admin
from firebase_admin import credentials, firestore

# Initialize Firebase
cred = credentials.Certificate('service_account.json')
try:
    firebase_admin.initialize_app(cred)
except ValueError:
    pass
db = firestore.client()

PROJECT_IDS = {
    "37x35 2BHK":        "0c78434d-9dc5-468a-802f-5db27c4fe0c9",
    "37x49 4BHK 2Storey": "0fb34ddd-6898-4aa2-aa7f-ab93b51d46c3",
    "43x54 2BHK 2Storey": "3cdf0520-0dda-4666-b67b-2f8059a7a71a",
    "house_plan":         "d1a6cf6e-0585-4b25-81eb-77ee8a9e37cf",
    "30x50 2BHK":         "d47b318e-15de-4332-9316-f5a77c651896",
    "40x50 3BHK":         "dc213e61-4bf9-4f9f-97ae-37f63cea1ce5",
    "Commercial 4Storey": "e20cead9-d543-4dde-a81a-2c6dc91c4cd0",
    "22x24 1BHK":         "fd9d20fd-8441-4bb1-be93-4f17cb93dd7f",
}

# Configuration for each project to control its timeline, deviation status, and vendor bills.
# Statuses: 'active', 'completed', 'closed', 'planning'
PROJECT_CONFIG = {
    # 2 Newly Created Projects
    "37x35 2BHK":        {"elapsed": 10,  "total": 300, "status": "active", "bias": (1.0, 1.0, 1.0),    "var": (0.95, 1.05), "bills": 2,  "state": "Normal"},
    "22x24 1BHK":        {"elapsed": 10,  "total": 300, "status": "active", "bias": (1.10, 1.05, 1.12), "var": (0.95, 1.05), "bills": 1,  "state": "Warning"},
    
    # 2 Middle Progress Projects
    "30x50 2BHK":        {"elapsed": 150, "total": 300, "status": "active", "bias": (0.98, 0.95, 1.02), "var": (0.95, 1.05), "bills": 6,  "state": "Normal"},
    "40x50 3BHK":        {"elapsed": 150, "total": 300, "status": "active", "bias": (1.15, 1.12, 1.08), "var": (0.95, 1.05), "bills": 5,  "state": "Warning"},
    
    # 2 About to End Projects
    "43x54 2BHK 2Storey": {"elapsed": 285, "total": 300, "status": "active", "bias": (1.0, 0.98, 1.02), "var": (0.95, 1.05), "bills": 15, "state": "Normal"},
    "house_plan":         {"elapsed": 285, "total": 300, "status": "active", "bias": (1.30, 1.25, 1.35), "var": (0.95, 1.10), "bills": 18, "state": "Critical"},
    
    # 1 Completed & Closed
    "37x49 4BHK 2Storey": {"elapsed": 300, "total": 300, "status": "closed", "bias": (1.0, 1.0, 1.0),    "var": (0.95, 1.05), "bills": 20, "state": "Completed (Normal)"},
    
    # 1 Completed fully but NOT Closed
    "Commercial 4Storey": {"elapsed": 300, "total": 300, "status": "active", "bias": (1.45, 1.38, 1.52), "var": (0.95, 1.15), "bills": 25, "state": "Critical (Timeline Over)"},
}

def extract_material_value(material_data):
    if isinstance(material_data, dict):
        return float(material_data.get('quantity', 0))
    return float(material_data)

def delete_collection(coll_ref, batch_size=100):
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0
    for doc in docs:
        doc.reference.delete()
        deleted += 1
    if deleted >= batch_size:
        return delete_collection(coll_ref, batch_size)

def main():
    summary_data = []

    for name, project_id in PROJECT_IDS.items():
        config = PROJECT_CONFIG.get(name)
        if not config:
            continue
            
        print(f"Processing project {name} ({project_id})...")
        
        # STEP 0: Clean up old logs and bills
        logs_ref = db.collection('projects').document(project_id).collection('resourceLogs')
        delete_collection(logs_ref)
        bills_ref = db.collection('projects').document(project_id).collection('vendorBills')
        delete_collection(bills_ref)
        
        # STEP 1: Update project document timeline and status
        now = datetime.now()
        start_date = now - timedelta(days=config["elapsed"])
        end_date = start_date + timedelta(days=config["total"])
        
        db.collection('projects').document(project_id).update({
            'createdAt': start_date,
            'startDate': start_date,
            'expectedEndDate': end_date,
            'status': config["status"],
            'durationDays': config["total"]
        })
        
        # Read estimates
        estimates_ref = db.collection('projects').document(project_id).collection('estimates')
        estimates_docs = list(estimates_ref.order_by('generatedAt', direction=firestore.Query.DESCENDING).limit(1).stream())
        
        if not estimates_docs:
            print(f"  WARNING: No estimates found for {name}. Skipping.")
            continue
            
        estimate_data = estimates_docs[0].to_dict()
        materials = estimate_data.get('estimatedMaterials', {})
        
        est_cement = extract_material_value(materials.get('cement', 0))
        est_bricks = extract_material_value(materials.get('bricks', 0))
        est_steel = extract_material_value(materials.get('steel', 0))
        est_sand = extract_material_value(materials.get('sand', 0))
        est_aggregate = extract_material_value(materials.get('aggregate', 0))

        # We will distribute logs across elapsed days
        days = config["elapsed"]
        daily_cement = est_cement / config["total"] if config["total"] else 0
        daily_bricks = est_bricks / config["total"] if config["total"] else 0
        daily_steel = est_steel / config["total"] if config["total"] else 0
        daily_sand = est_sand / config["total"] if config["total"] else 0
        daily_aggregate = est_aggregate / config["total"] if config["total"] else 0
        
        bias_factors = config["bias"]
        var_range = config["var"]
        total_logged_cement = 0
        
        # STEP 2: Generate Logs
        for i in range(days, 0, -1):
            log_date = now - timedelta(days=i)
            variation = random.uniform(var_range[0], var_range[1])
            
            cement_used = daily_cement * bias_factors[0] * variation
            bricks_used = daily_bricks * bias_factors[1] * variation
            steel_used = daily_steel * bias_factors[2] * variation
            sand_used = daily_sand * bias_factors[0] * variation
            aggregate_used = daily_aggregate * bias_factors[0] * variation
            
            total_logged_cement += cement_used
            
            log_data = {
                'projectId': project_id,
                'logDate': log_date,
                'date': log_date,
                'materialUsage': {
                    'cement_bags': round(cement_used, 1),
                    'bricks': round(bricks_used, 0),
                    'steel_kg': round(steel_used, 1),
                    'sand_m3': round(sand_used, 2),
                    'aggregate_m3': round(aggregate_used, 2),
                },
                'laborHours': random.randint(45, 80),
                'weatherCondition': random.choice(['sunny','sunny','sunny','cloudy','rainy']),
                'isWeatherDelay': False,
                'equipment': [
                    {
                        'name': 'Concrete Mixer',
                        'hoursUsed': random.randint(4, 8),
                        'hoursIdle': random.randint(0, 2),
                    },
                    {
                        'name': 'JCB Excavator', 
                        'hoursUsed': random.randint(3, 6),
                        'hoursIdle': random.randint(1, 3),
                    },
                ],
                'notes': '',
                'loggedBy': 'seeded',
                'createdAt': log_date,
            }
            logs_ref.add(log_data)
            
        # STEP 3: Generate Vendor Bills
        num_bills = config["bills"]
        if num_bills > 0:
            # Spread the total estimated usage across the bills up to the elapsed fraction
            elapsed_fraction = days / config["total"]
            
            total_billed_cement = est_cement * elapsed_fraction * bias_factors[0]
            total_billed_bricks = est_bricks * elapsed_fraction * bias_factors[1]
            total_billed_steel = est_steel * elapsed_fraction * bias_factors[2]
            
            cement_per_bill = total_billed_cement / num_bills
            bricks_per_bill = total_billed_bricks / num_bills
            steel_per_bill = total_billed_steel / num_bills
            
            bill_interval = max(1, days // num_bills)
            
            vendors = ['Sharma Building Materials', 'Steel Tech Pvt Ltd', 'Balaji Aggregates', 'City Hardware']
            
            for b in range(num_bills):
                bill_date = start_date + timedelta(days=(b + 1) * bill_interval)
                if bill_date > now:
                    bill_date = now
                    
                line_items = []
                subtotal = 0
                
                # Add cement
                if cement_per_bill > 0:
                    qty = round(cement_per_bill * random.uniform(0.9, 1.1), 0)
                    amt = round(qty * 380, 0)
                    line_items.append({'material': 'Cement', 'quantity': qty, 'unit': 'bags', 'ratePerUnit': 380, 'amount': amt})
                    subtotal += amt
                    
                # Add bricks
                if bricks_per_bill > 0:
                    qty = round(bricks_per_bill * random.uniform(0.9, 1.1), 0)
                    amt = round(qty * 8, 0)
                    line_items.append({'material': 'Bricks', 'quantity': qty, 'unit': 'pcs', 'ratePerUnit': 8, 'amount': amt})
                    subtotal += amt
                    
                # Add steel
                if steel_per_bill > 0:
                    qty = round(steel_per_bill * random.uniform(0.9, 1.1), 0)
                    amt = round(qty * 65, 0)
                    line_items.append({'material': 'Steel', 'quantity': qty, 'unit': 'kg', 'ratePerUnit': 65, 'amount': amt})
                    subtotal += amt

                bill_data = {
                    'vendorName': random.choice(vendors),
                    'invoiceNumber': f'INV-{project_id[:6]}-{1000 + b}',
                    'date': bill_date,
                    'items': line_items,
                    'amount': round(subtotal * 1.18, 2),
                    'subtotal': subtotal,
                    'gst': round(subtotal * 0.18, 2),
                    'category': 'Materials',
                    'fileUrl': '',
                    'uploadedBy': 'seeded',
                    'status': 'paid',
                    'createdAt': bill_date,
                    'projectId': project_id
                }
                bills_ref.add(bill_data)

        # Calculate deviation for summary
        expected_cement_elapsed = est_cement * (days / config["total"])
        deviation_pct = ((total_logged_cement / expected_cement_elapsed) - 1.0) * 100 if expected_cement_elapsed else 0
        
        summary_data.append({
            'name': name,
            'state': config["state"],
            'elapsed': days,
            'bills': num_bills,
            'deviation_pct': deviation_pct
        })
        print(f"  Done: {days} logs, {num_bills} bills written.")

    print("\n=== SUMMARY ===")
    for s in summary_data:
        print(f"Project: {s['name']} ({s['state']})")
        print(f"  {s['elapsed']} logs written, {s['bills']} bills written")
        print(f"  Projected Deviation (Cement): {s['deviation_pct']:.1f}%")
        print()

if __name__ == '__main__':
    main()
