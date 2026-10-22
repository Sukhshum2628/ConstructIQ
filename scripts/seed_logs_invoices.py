import sys
import os
import random
import uuid
from datetime import datetime, timedelta
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

# Deterministic Site Engineer UIDs
ENGINEER_UIDS = [
    '8fpCTaXTuKXpX349GGjt1DHQuPB3', # KaranENG
    'KP8zBoY7DyTy43grL0fDEV9gnS12', # Karan Eng
    'kVAawiRK00XQpKjXUfuAQGyXIHz1', # Sukhshum
]

PROJECTS_CONFIG = {
    "0c78434d-9dc5-468a-802f-5db27c4fe0c9": {
        "name": "37x35 2BHK", 
        "log_days": 10, 
        "completion_pct": 0.11,
        "bias": (1.01, 1.01, 1.01) # Very small, clean deviation
    },
    "0fb34ddd-6898-4aa2-aa7f-ab93b51d46c3": {
        "name": "37x49 4BHK 2Storey", 
        "log_days": 25, 
        "completion_pct": 0.28,
        "bias": (1.02, 1.01, 1.03) # Clean deviation
    },
    "3cdf0520-0dda-4666-b67b-2f8059a7a71a": {
        "name": "43x54 2BHK 2Storey", 
        "log_days": 45, 
        "completion_pct": 0.50,
        "bias": (0.97, 0.98, 0.96) # Clean deviation
    },
    "d1a6cf6e-0585-4b25-81eb-77ee8a9e37cf": {
        "name": "house_plan", 
        "log_days": 90, 
        "completion_pct": 0.75,
        "bias": (1.03, 1.02, 1.04) # Clean deviation
    },
    "d47b318e-15de-4332-9316-f5a77c651896": {
        "name": "30x50 2BHK", 
        "log_days": 60, 
        "completion_pct": 0.66,
        "bias": (1.02, 1.01, 1.03) # Clean deviation
    },
    "dc213e61-4bf9-4f9f-97ae-37f63cea1ce5": {
        "name": "40x50 3BHK", 
        "log_days": 30, 
        "completion_pct": 0.33,
        "bias": (0.98, 0.99, 0.97) # Clean deviation
    },
    "e20cead9-d543-4dde-a81a-2c6dc91c4cd0": {
        "name": "Commercial 4Storey", 
        "log_days": 120, 
        "completion_pct": 0.85,
        "bias": (1.04, 1.03, 1.05) # Clean deviation
    },
    "fd9d20fd-8441-4bb1-be93-4f17cb93dd7f": {
        "name": "22x24 1BHK", 
        "log_days": 15, 
        "completion_pct": 0.17,
        "bias": (1.01, 1.01, 1.02) # Clean deviation
    },
}

def read_qty(mats, key):
    if not mats:
        return 0.0
    val = mats.get(key)
    if val is None:
        return 0.0
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, dict):
        return float(val.get('quantity', 0.0))
    return 0.0

def get_estimate_qty(mats, key):
    if key == 'cement':
        return read_qty(mats, 'cement') + read_qty(mats, 'cement_bags')
    elif key == 'bricks':
        return read_qty(mats, 'bricks') + read_qty(mats, 'brick') + read_qty(mats, 'bricks_pcs')
    elif key == 'steel':
        return read_qty(mats, 'steel') + read_qty(mats, 'steel_kg') + read_qty(mats, 'rebar')
    elif key == 'sand':
        return read_qty(mats, 'sand') + read_qty(mats, 'sand_m3')
    elif key == 'aggregate':
        return read_qty(mats, 'aggregate') + read_qty(mats, 'aggregate_m3')
    return 0.0

print("Starting correctly calibrated seeding of resourceLogs and vendorBills...")

for pid, cfg in PROJECTS_CONFIG.items():
    name = cfg["name"]
    log_days = cfg["log_days"]
    completion_pct = cfg["completion_pct"]
    bias = cfg["bias"]
    
    print(f"\nProcessing project: {name} (ID: {pid})")
    
    # Read the project document to get the start and end dates
    project_doc = db.collection("projects").document(pid).get()
    project_data = project_doc.to_dict() or {}
    start_date = project_data.get("startDate")
    end_date = project_data.get("endDate")
    
    if start_date and end_date:
        today = datetime.now()
        start = start_date.datetime_value if hasattr(start_date, 'datetime_value') else (start_date.to_datetime() if hasattr(start_date, 'to_datetime') else start_date)
        end = end_date.datetime_value if hasattr(end_date, 'datetime_value') else (end_date.to_datetime() if hasattr(end_date, 'to_datetime') else end_date)
        
        # Strip timezones for local datetime calculations
        if hasattr(start, 'tzinfo') and start.tzinfo is not None:
            start = start.replace(tzinfo=None)
        if hasattr(end, 'tzinfo') and end.tzinfo is not None:
            end = end.replace(tzinfo=None)
        today = today.replace(tzinfo=None)
        
        total_project_days = (end - start).days
        days_elapsed = (today - start).days
        
        # Ensure that actual_log_days dynamically targets the completion percentage,
        # but is at least 10 days for newly-started projects to ensure sufficient graphs
        actual_log_days = max(10, int(total_project_days * completion_pct))
        
        # If elapsed days are actually smaller, let's keep actual_log_days at max(10, days_elapsed)
        actual_log_days = max(actual_log_days, min(days_elapsed, total_project_days))
        actual_log_days = max(10, actual_log_days)  # Strict minimum of 10 logs
        
        # Re-align total_project_days to match completion pct to prevent unrealistic pro-rated logic
        total_project_days = max(total_project_days, int(actual_log_days / completion_pct))
    else:
        # Fallback to hardcoded values if dates not found
        actual_log_days = max(10, log_days)
        total_project_days = int(actual_log_days / completion_pct)
        days_elapsed = actual_log_days
        
    print(f"  Timeline — Total Days: {total_project_days}, Days Elapsed: {days_elapsed}, Log Days to Generate: {actual_log_days}")
    
    # A) Read the real estimatedMaterials from Firestore latest estimate
    estimates_ref = db.collection("projects").document(pid).collection("estimates")
    estimates = list(estimates_ref.order_by("generatedAt", direction=firestore.Query.DESCENDING).limit(1).stream())
    
    estimated_mats = {}
    if estimates:
        estimated_mats = estimates[0].to_dict().get("estimatedMaterials", {})
        print(f"  Loaded estimate document successfully: {estimates[0].id}")
    else:
        print(f"  WARNING: No estimate document found for {name}! Using fallback estimation values.")
        estimated_mats = {
            "cement": {"quantity": 800, "unit": "bags"},
            "bricks": {"quantity": 25000, "unit": "nos"},
            "steel": {"quantity": 4000, "unit": "kg"},
            "sand": {"quantity": 80, "unit": "m3"},
            "aggregate": {"quantity": 120, "unit": "m3"}
        }
    
    est_cement = get_estimate_qty(estimated_mats, 'cement')
    est_bricks = get_estimate_qty(estimated_mats, 'bricks')
    est_steel = get_estimate_qty(estimated_mats, 'steel')
    est_sand = get_estimate_qty(estimated_mats, 'sand')
    est_agg = get_estimate_qty(estimated_mats, 'aggregate')
    
    print(f"  Estimated — cement: {est_cement:.1f}, bricks: {est_bricks:.0f}, steel: {est_steel:.1f}, sand: {est_sand:.1f}, aggregate: {est_agg:.1f}")

    # B) Calculate daily base quantities (divided by total_project_days)
    daily_cement = est_cement / total_project_days if total_project_days > 0 else est_cement
    daily_bricks = est_bricks / total_project_days if total_project_days > 0 else est_bricks
    daily_steel = est_steel / total_project_days if total_project_days > 0 else est_steel
    daily_sand = est_sand / total_project_days if total_project_days > 0 else est_sand
    daily_aggregate = est_agg / total_project_days if total_project_days > 0 else est_agg

    # C) Generate actual_log_days of log entries with custom bias and distinct random variation per material
    logs_data = []
    total_consumed = {'cement': 0.0, 'bricks': 0.0, 'steel': 0.0, 'sand': 0.0, 'aggregate': 0.0}
    
    for i in range(actual_log_days, 0, -1):
        date = datetime.now() - timedelta(days=i)
        
        # Vary each material independently to prevent identical flat-line trends
        cement_var = random.uniform(0.92, 1.08)
        bricks_var = random.uniform(0.90, 1.06)
        steel_var  = random.uniform(0.94, 1.08)
        sand_var   = random.uniform(0.91, 1.07)
        agg_var    = random.uniform(0.89, 1.05)
        
        # Round quantities to exactly 1 decimal place
        cement = round(daily_cement * bias[0] * cement_var, 1)
        bricks = round(daily_bricks * bias[1] * bricks_var, 1)
        steel  = round(daily_steel  * bias[2] * steel_var, 1)
        sand   = round(daily_sand   * bias[0] * sand_var, 1)
        agg    = round(daily_aggregate * bias[0] * agg_var, 1)
        
        # Select deterministically a site engineer UID based on index
        engineer_uid = ENGINEER_UIDS[i % len(ENGINEER_UIDS)]
        
        logs_data.append({
            'date': date,
            'cement': cement,
            'bricks': bricks,
            'steel': steel,
            'sand': sand,
            'aggregate': agg,
            'loggedBy': engineer_uid
        })
        
        total_consumed['cement']    += cement
        total_consumed['bricks']    += bricks
        total_consumed['steel']     += steel
        total_consumed['sand']      += sand
        total_consumed['aggregate'] += agg

    # D) Generate 3 invoices BASED ON total_consumed with 20% buffer
    total_delivered_cement    = total_consumed['cement']    * 1.20
    total_delivered_bricks    = total_consumed['bricks']    * 1.20
    total_delivered_steel     = total_consumed['steel']     * 1.20
    total_delivered_sand      = total_consumed['sand']      * 1.20
    total_delivered_aggregate = total_consumed['aggregate'] * 1.20
    
    # CPWD Rates & Units
    rates = {
        'cement': 400.0,
        'bricks': 12.0,
        'steel': 70.0,
        'sand': 95.0 * 35.3147,        # Sand rate converted to m3
        'aggregate': 140.0 * 35.3147   # Aggregate rate converted to m3
    }
    
    units = {
        'cement': 'bags',
        'bricks': 'nos',
        'steel': 'kg',
        'sand': 'm3',
        'aggregate': 'm3'
    }
    
    descriptions = {
        'cement': 'Grade 53 OPC Cement',
        'bricks': 'Red Clay Masonry Bricks',
        'steel': 'Fe 550D TMT Rebar Steel',
        'sand': 'High quality River Sand',
        'aggregate': 'Coarse Aggregate (20mm)'
    }
    
    def make_bill_item(material, qty):
        rate = rates[material]
        amount = round(qty * rate, 1)
        return {
            'description': descriptions[material],
            'quantity': round(qty, 1),
            'unit': units[material],
            'rate': round(rate, 1),
            'amount': amount
        }

    # Invoice 1 (actual_log_days days ago) — 40% of total
    i1_cement = total_delivered_cement * 0.40
    i1_bricks = total_delivered_bricks * 0.40
    i1_steel  = total_delivered_steel  * 0.40
    i1_sand   = total_delivered_sand   * 0.40
    i1_agg    = total_delivered_aggregate * 0.40
    
    i1_items = [
        make_bill_item('cement', i1_cement),
        make_bill_item('bricks', i1_bricks),
        make_bill_item('steel', i1_steel),
        make_bill_item('sand', i1_sand),
        make_bill_item('aggregate', i1_agg)
    ]
    i1_amount = round(sum(item['amount'] for item in i1_items), 1)
    
    # Invoice 2 (actual_log_days//2 days ago) — 35% of total (Cement, Bricks, Steel only)
    i2_cement = total_delivered_cement * 0.35
    i2_bricks = total_delivered_bricks * 0.35
    i2_steel  = total_delivered_steel  * 0.35
    
    i2_items = [
        make_bill_item('cement', i2_cement),
        make_bill_item('bricks', i2_bricks),
        make_bill_item('steel', i2_steel)
    ]
    i2_amount = round(sum(item['amount'] for item in i2_items), 1)
    
    # Invoice 3 (7 days ago) — 25% of Cement/Bricks/Steel, 60% of Sand/Aggregate
    i3_cement = total_delivered_cement * 0.25
    i3_bricks = total_delivered_bricks * 0.25
    i3_steel  = total_delivered_steel  * 0.25
    i3_sand   = total_delivered_sand   * 0.60
    i3_agg    = total_delivered_aggregate * 0.60
    
    i3_items = [
        make_bill_item('cement', i3_cement),
        make_bill_item('bricks', i3_bricks),
        make_bill_item('steel', i3_steel),
        make_bill_item('sand', i3_sand),
        make_bill_item('aggregate', i3_agg)
    ]
    i3_amount = round(sum(item['amount'] for item in i3_items), 1)
    
    invoices = [
        {
            'date': datetime.now() - timedelta(days=actual_log_days),
            'vendor': 'BuildStore Materials Ltd',
            'category': 'Construction Materials',
            'amount': i1_amount,
            'items': i1_items
        },
        {
            'date': datetime.now() - timedelta(days=max(1, actual_log_days // 2)),
            'vendor': 'Masonry Supply Co',
            'category': 'Brick & Cement Hub',
            'amount': i2_amount,
            'items': i2_items
        },
        {
            'date': datetime.now() - timedelta(days=7),
            'vendor': 'Steel & Foundation Tech',
            'category': 'Heavy Materials & Metals',
            'amount': i3_amount,
            'items': i3_items
        }
    ]

    # E) NOW write to Firestore (Invoices first, then Resource Logs)
    print("  Writing Invoices (vendorBills)...")
    for idx, inv in enumerate(invoices):
        inv_id = str(uuid.uuid4())
        inv_doc = {
            'id': inv_id,
            'projectId': pid,
            'vendorName': inv['vendor'],
            'amount': inv['amount'],
            'date': inv['date'],
            'category': inv['category'],
            'fileUrl': 'https://example.com/invoice.pdf',
            'uploadedBy': 'VC3G0ZmK6cTpYt7SUmcmvopF7F72', # Sukhshum manager UID
            'items': inv['items'],
            'createdAt': datetime.now()
        }
        db.collection("projects").document(pid).collection("vendorBills").document(inv_id).set(inv_doc)
        
    print("  Writing Daily Resource Logs (resourceLogs)...")
    for idx, log in enumerate(logs_data):
        log_id = str(uuid.uuid4())
        log_doc = {
            'id': log_id,
            'projectId': pid,
            'date': log['date'],
            'loggedBy': log['loggedBy'],
            'materialUsage': {
                'cement': round(log['cement'], 1),
                'bricks': round(log['bricks'], 1),
                'steel': round(log['steel'], 1),
                'sand': round(log['sand'], 1),
                'aggregate': round(log['aggregate'], 1)
            },
            # Real equipment list to display utilization metrics in intelligence section
            'equipment': [
                {
                    'name': 'Excavator', 
                    'usedHours': float(round(random.uniform(4.5, 7.5), 1)), 
                    'idleHours': float(round(random.uniform(0.5, 2.5), 1))
                },
                {
                    'name': 'Tower Crane', 
                    'usedHours': float(round(random.uniform(3.5, 6.5), 1)), 
                    'idleHours': float(round(random.uniform(1.0, 3.0), 1))
                },
                {
                    'name': 'Concrete Mixer', 
                    'usedHours': float(round(random.uniform(5.0, 8.0), 1)), 
                    'idleHours': float(round(random.uniform(0.2, 1.8), 1))
                }
            ],
            'weather': random.choice(['Sunny', 'Sunny', 'Partly Cloudy', 'Rainy' if actual_log_days > 30 else 'Sunny']),
            'laborCount': random.randint(8, 18),
            'progressNotes': f"Daily construction progress logged for day {idx+1}. Structural works and masonry continuing.",
            'createdAt': log['date']
        }
        db.collection("projects").document(pid).collection("resourceLogs").document(log_id).set(log_doc)

    # F) Print summary for verification
    print(f"\nProject {name}:")
    print(f"  Total project days: {total_project_days}")
    print(f"  Days elapsed: {days_elapsed}")
    print(f"  Log days generated: {actual_log_days}")
    print(f"  Total consumed — cement: {total_consumed['cement']:.1f}, bricks: {total_consumed['bricks']:.0f}, steel: {total_consumed['steel']:.1f}")
    print(f"  Total delivered — cement: {total_delivered_cement:.1f}, bricks: {total_delivered_bricks:.0f}, steel: {total_delivered_steel:.1f}")
    print(f"  Delivered > Consumed: cement={total_delivered_cement > total_consumed['cement']}, bricks={total_delivered_bricks > total_consumed['bricks']}, steel={total_delivered_steel > total_consumed['steel']}")

print("\nAll projects successfully seeded with consistent, highly-calibrated, and validated data!")
