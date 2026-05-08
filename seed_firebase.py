"""
ConstructIQ - Firebase Seeding Script (Production)
====================================================
Uses REAL Firestore UIDs and the EXACT CPWD estimation formulas
from construction-ai-service/modules/estimation_engine.py

Material costs calculated using material_rates.dart rates:
  cement: 400/bag, bricks: 12/nos, steel: 70/kg
  sand: 95/cuft (x35.3147 for m3), aggregate: 140/cuft (x35.3147 for m3)

Budget = materialCost * 2.5 (matches app's Total Project Est. formula)

Run: python seed_firebase.py
"""

import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, timedelta, timezone
import random
import math
import sys

# -- Init --
try:
    cred = credentials.Certificate("construction-ai-service/service_account.json")
    firebase_admin.initialize_app(cred)
except Exception as e:
    print(f"Error initializing Firebase: {e}")
    sys.exit(1)

db = firestore.client()

# ==================================================
# REAL FIRESTORE UIDs
# ==================================================

MANAGERS = {
    "VC3G0ZmK6cTpYt7SUmcmvopF7F72": "Sukhshum Vaishnavi",
    "4M5jTGN6gJNhcQEw92IIVUZMfmx1": "Akash Vaishnavi",
    "FaDVXpBgFnYnKBCYpYc9Nf2FMg12": "Mohit Koul",
    "LXpAEnUGCeaFvHBQdlqwWOEGE3I2": "KaranMGR",
    "xqXTN92vnwWQ5uWhjBDVhZgYokj1": "mohit mgr",
}

ENGINEERS = {
    "8fpCTaXTuKXpX349GGjt1DHQuPB3": "KaranENG",
    "kVAawiRK0OXQpKjXUfuAQGyXIHZ1": "Sukhshum",
}

MGR_UIDS = list(MANAGERS.keys())
ENG_UIDS = list(ENGINEERS.keys())

MATERIALS = ["cement", "bricks", "sand", "steel", "aggregate"]

EQUIPMENT_TYPES = [
    "Excavator E-04",
    "Concrete Mixer M-12",
    "Tower Crane C-09",
    "Dump Truck T-22",
    "Backhoe Loader B-05",
]

VENDOR_NAMES = [
    "Ambuja Cements Ltd",
    "UltraTech Concrete",
    "Tata Steel Pvt Ltd",
    "ACC Aggregates",
    "JK Lakshmi Cement",
    "Shree Cement Ltd",
    "Dalmia Bharat Ltd",
    "JSW Steel",
]


# ==================================================
# EXACT CPWD ESTIMATION ENGINE
# (ported from estimation_engine.py calculate_materials)
# ==================================================
def cpwd_estimate(geo):
    """
    Exact port of estimation_engine.py calculate_materials().
    Input: dict with totalWallLength, totalFloorArea, floorCount,
           doorCount, windowCount, beamLength, totalColumnCount, stairArea
    Output: dict of material -> {quantity, unit}
    """
    STANDARD_HEIGHT = 3.0
    SLAB_THICKNESS = 0.15

    # Derive wall area from wall length
    wall_area = geo["totalWallLength"] * STANDARD_HEIGHT
    floor_area = geo["totalFloorArea"]
    concrete_vol = floor_area * SLAB_THICKNESS
    floor_count = geo.get("floorCount", 1)
    door_count = geo.get("doorCount", 0)
    window_count = geo.get("windowCount", 0)
    beam_length = geo.get("beamLength", 0)
    column_count = geo.get("totalColumnCount", 0)
    stair_area = geo.get("stairArea", 0)
    height = geo.get("buildingHeight", STANDARD_HEIGHT)

    # Opening deductions (CPWD norms)
    DOOR_AREA = 0.9 * 2.1    # 1.89 m2 per door
    WINDOW_AREA = 1.2 * 1.2  # 1.44 m2 per window
    opening_area = (door_count * DOOR_AREA) + (window_count * WINDOW_AREA)
    net_wall_area = max(0.0, wall_area - opening_area)

    # Brick masonry
    total_bricks = net_wall_area * 190
    cement_masonry = net_wall_area * 0.85
    sand_masonry = net_wall_area * 0.15

    # RCC Structure
    cement_slab = concrete_vol * 8.2
    sand_slab = concrete_vol * 0.45
    aggregate_slab = concrete_vol * 0.85
    steel_slab = concrete_vol * 75.0

    # Staircase
    stair_vol = stair_area * 0.20
    cement_stair = stair_vol * 8
    aggregate_stair = stair_vol * 0.84

    # Beams
    beam_vol = beam_length * 0.069
    cement_beam = beam_vol * 8
    aggregate_beam = beam_vol * 0.84
    steel_beam = beam_vol * 7850 * 0.02

    # Columns
    col_vol = column_count * 0.053 * height
    cement_col = col_vol * 8
    aggregate_col = col_vol * 0.84
    steel_col = col_vol * 7850 * 0.03

    # Plastering (both sides of walls)
    plaster_area = wall_area * 1.8
    cement_plaster = plaster_area * 0.11
    sand_plaster = plaster_area * 0.022

    # Floor screed
    cement_screed = floor_area * 0.044
    sand_screed = floor_area * 0.008

    # Totals
    total_cement = (cement_masonry + cement_slab + cement_stair +
                    cement_beam + cement_col + cement_plaster + cement_screed)
    total_sand = sand_masonry + sand_slab + sand_plaster + sand_screed
    total_aggregate = aggregate_slab + aggregate_stair + aggregate_beam + aggregate_col
    total_steel = steel_slab + steel_beam + steel_col

    return {
        "cement":    {"quantity": round(total_cement, 1),    "unit": "bags"},
        "bricks":    {"quantity": int(total_bricks),         "unit": "nos"},
        "steel":     {"quantity": round(total_steel, 1),     "unit": "kg"},
        "sand":      {"quantity": round(total_sand, 2),      "unit": "m3"},
        "aggregate": {"quantity": round(total_aggregate, 2), "unit": "m3"},
    }


# ==================================================
# MATERIAL COST (matches material_rates.dart exactly)
# ==================================================
RATES = {
    "cement":    400.0,
    "bricks":    12.0,
    "steel":     70.0,
    "sand":      95.0 * 35.3147,    # per m3 (cuft rate * conversion)
    "aggregate": 140.0 * 35.3147,   # per m3 (cuft rate * conversion)
}

def calc_material_cost(est_materials):
    total = 0.0
    for mat, data in est_materials.items():
        total += data["quantity"] * RATES[mat]
    return total


# ==================================================
# 10 RESIDENTIAL PROJECTS
# Realistic geometry for Indian residential houses/buildings
#
# Floor areas in m2 (per floor):
#   2BHK house: 80-110 m2
#   3BHK house: 120-150 m2
#   Duplex: 110-140 m2
#   3-storey bldg: 150-200 m2 per floor
#   4-storey bldg: 180-250 m2 per floor
#
# Wall lengths are actual perimeter + internal walls
# Door/window counts are realistic per room count
# Columns/beams for RCC frame buildings
# ==================================================
today = datetime.now(timezone.utc)

PROJECTS_DATA = [
    {
        "id": "sharma_2bhk_house",
        "name": "Sharma 2BHK House",
        "location": "Sector 12, Jammu",
        "status": "active",
        "days_ago": 45,
        "duration": 120,
        "manager": MGR_UIDS[0],
        "geo": {
            "totalWallLength": 52.0,
            "totalFloorArea": 95.0,
            "floorCount": 1,
            "doorCount": 6,
            "windowCount": 5,
            "beamLength": 28.0,
            "totalColumnCount": 8,
            "stairArea": 0,
        },
    },
    {
        "id": "gupta_3bhk_house",
        "name": "Gupta 3BHK House",
        "location": "Gandhi Nagar, Jammu",
        "status": "active",
        "days_ago": 30,
        "duration": 150,
        "manager": MGR_UIDS[0],
        "geo": {
            "totalWallLength": 78.0,
            "totalFloorArea": 140.0,
            "floorCount": 2,
            "doorCount": 10,
            "windowCount": 8,
            "beamLength": 52.0,
            "totalColumnCount": 12,
            "stairArea": 8.5,
        },
    },
    {
        "id": "mehta_2bhk_house",
        "name": "Mehta 2BHK House",
        "location": "Rehari Colony, Jammu",
        "status": "active",
        "days_ago": 20,
        "duration": 100,
        "manager": MGR_UIDS[1],
        "geo": {
            "totalWallLength": 48.0,
            "totalFloorArea": 85.0,
            "floorCount": 1,
            "doorCount": 5,
            "windowCount": 4,
            "beamLength": 22.0,
            "totalColumnCount": 6,
            "stairArea": 0,
        },
    },
    {
        "id": "koul_duplex_house",
        "name": "Koul Duplex House",
        "location": "Channi Himmat, Jammu",
        "status": "active",
        "days_ago": 60,
        "duration": 180,
        "manager": MGR_UIDS[1],
        "geo": {
            "totalWallLength": 68.0,
            "totalFloorArea": 125.0,
            "floorCount": 2,
            "doorCount": 9,
            "windowCount": 7,
            "beamLength": 45.0,
            "totalColumnCount": 10,
            "stairArea": 9.0,
        },
    },
    {
        "id": "singh_3storey_building",
        "name": "Singh 3-Storey Building",
        "location": "Trikuta Nagar, Jammu",
        "status": "active",
        "days_ago": 90,
        "duration": 270,
        "manager": MGR_UIDS[2],
        "geo": {
            "totalWallLength": 110.0,
            "totalFloorArea": 220.0,
            "floorCount": 3,
            "doorCount": 18,
            "windowCount": 15,
            "beamLength": 95.0,
            "totalColumnCount": 20,
            "stairArea": 14.0,
        },
    },
    {
        "id": "verma_2storey_house",
        "name": "Verma 2-Storey House",
        "location": "Bakshi Nagar, Jammu",
        "status": "active",
        "days_ago": 75,
        "duration": 150,
        "manager": MGR_UIDS[2],
        "geo": {
            "totalWallLength": 62.0,
            "totalFloorArea": 110.0,
            "floorCount": 2,
            "doorCount": 8,
            "windowCount": 6,
            "beamLength": 38.0,
            "totalColumnCount": 10,
            "stairArea": 7.5,
        },
    },
    {
        "id": "reddy_4storey_building",
        "name": "Reddy 4-Storey Building",
        "location": "Janipur, Jammu",
        "status": "completed",
        "days_ago": 220,
        "duration": 200,
        "manager": MGR_UIDS[3],
        "geo": {
            "totalWallLength": 135.0,
            "totalFloorArea": 280.0,
            "floorCount": 4,
            "doorCount": 24,
            "windowCount": 20,
            "beamLength": 120.0,
            "totalColumnCount": 28,
            "stairArea": 18.0,
        },
    },
    {
        "id": "kapoor_2bhk_house",
        "name": "Kapoor 2BHK House",
        "location": "Patnitop Road, Udhampur",
        "status": "closed",
        "days_ago": 150,
        "duration": 100,
        "manager": MGR_UIDS[3],
        "geo": {
            "totalWallLength": 46.0,
            "totalFloorArea": 82.0,
            "floorCount": 1,
            "doorCount": 5,
            "windowCount": 4,
            "beamLength": 20.0,
            "totalColumnCount": 6,
            "stairArea": 0,
        },
    },
    {
        "id": "thakur_3bhk_house",
        "name": "Thakur 3BHK House",
        "location": "Kunjwani, Jammu",
        "status": "active",
        "days_ago": 10,
        "duration": 160,
        "manager": MGR_UIDS[4],
        "geo": {
            "totalWallLength": 74.0,
            "totalFloorArea": 135.0,
            "floorCount": 2,
            "doorCount": 9,
            "windowCount": 7,
            "beamLength": 48.0,
            "totalColumnCount": 12,
            "stairArea": 8.0,
        },
    },
    {
        "id": "dutta_2storey_house",
        "name": "Dutta 2-Storey House",
        "location": "Nanak Nagar, Jammu",
        "status": "active",
        "days_ago": 3,
        "duration": 130,
        "manager": MGR_UIDS[4],
        "geo": {
            "totalWallLength": 58.0,
            "totalFloorArea": 105.0,
            "floorCount": 2,
            "doorCount": 7,
            "windowCount": 6,
            "beamLength": 35.0,
            "totalColumnCount": 9,
            "stairArea": 7.0,
        },
    },
]


# ==================================================
# CLEANUP
# ==================================================
def delete_all_projects():
    print("Deleting old projects...")
    projects = db.collection("projects").stream()
    for p in projects:
        for sub in ["resourceLogs", "vendorBills", "estimates", "deviations", "delayNotices", "delays"]:
            docs = p.reference.collection(sub).stream()
            for d in docs:
                d.reference.delete()
        p.reference.delete()
    print("Cleanup complete.\n")


# ==================================================
# SEED
# ==================================================
def seed_data():
    for p in PROJECTS_DATA:
        pid = p["id"]
        mgr_uid = p["manager"]
        mgr_name = MANAGERS[mgr_uid]
        geo = p["geo"]

        start_date = today - timedelta(days=p["days_ago"])
        end_date = start_date + timedelta(days=p["duration"])

        # Run the EXACT CPWD estimation engine
        est_materials = cpwd_estimate(geo)

        # Calculate cost using app's material_rates.dart
        material_cost = calc_material_cost(est_materials)
        planned_budget = round(material_cost * 2.5)

        print(f"  [{p['status'].upper():>9}] {p['name']}")
        print(f"            Floor: {geo['totalFloorArea']} m2 | Wall: {geo['totalWallLength']} m | Floors: {geo['floorCount']}")
        print(f"            Doors: {geo['doorCount']} | Windows: {geo['windowCount']} | Columns: {geo['totalColumnCount']}")
        print(f"            Cement: {est_materials['cement']['quantity']} bags | Bricks: {est_materials['bricks']['quantity']} nos")
        print(f"            Steel: {est_materials['steel']['quantity']} kg | Sand: {est_materials['sand']['quantity']} m3")
        print(f"            CAD Cost: Rs {material_cost:,.0f} | Budget: Rs {planned_budget:,.0f}")

        # -- 1. PROJECT DOCUMENT --
        db.collection("projects").document(pid).set({
            "projectId": pid,
            "name": p["name"],
            "location": p["location"],
            "startDate": start_date,
            "expectedEndDate": end_date,
            "status": p["status"],
            "projectType": "residential",
            "plannedBudget": planned_budget,
            "createdBy": mgr_uid,
            "teamMembers": ENG_UIDS,
            "estimationStatus": "completed",
            "cadFileUrl": "",
            "createdAt": start_date - timedelta(days=2),
            "durationDays": p["duration"],
            "totalWallLength": geo["totalWallLength"],
            "totalFloorArea": geo["totalFloorArea"],
            "floorCount": geo["floorCount"],
        })

        # -- 2. ESTIMATES (using CPWD engine output) --
        est_id = f"est_{pid}"
        assumptions = [
            f"Wall area derived from wall length x 3.0m height",
            f"Concrete volume derived from floor area x 0.15m slab thickness",
            f"Opening deductions: {geo['doorCount']} doors, {geo['windowCount']} windows",
            f"RCC frame with {geo['totalColumnCount']} columns",
            "Seismic Zone IV compliance assumed",
        ]

        db.collection("projects").document(pid).collection("estimates").document(est_id).set({
            "estimateId": est_id,
            "generatedAt": start_date + timedelta(hours=2),
            "cadFileName": f"{pid}_blueprint.dxf",
            "geometryData": {
                "totalWallLength": geo["totalWallLength"],
                "totalFloorArea": geo["totalFloorArea"],
            },
            "estimatedMaterials": est_materials,
            "confidence": "high",
            "assumptions": assumptions,
        })

        # -- 3. RESOURCE LOGS (dynamic to timeline) --
        num_logs = min(p["days_ago"], 30)
        for i in range(num_logs):
            log_date = start_date + timedelta(days=i)
            lid = f"log_{pid}_{i}"

            daily_usage = {}
            for mat, data in est_materials.items():
                avg = data["quantity"] / p["duration"]
                val = avg * random.uniform(0.7, 1.3)
                if i % 7 == 0:
                    val *= random.uniform(1.3, 1.6)
                if mat == "steel" and i < 5:
                    val *= 2.0  # More steel in early foundation phase
                daily_usage[mat] = round(val, 2)

            equip_entries = []
            num_equip = random.randint(1, 3)
            for etype in random.sample(EQUIPMENT_TYPES, num_equip):
                used = round(random.uniform(3, 8), 1)
                idle = round(random.uniform(0.5, 2.5), 1)
                equip_entries.append({"name": etype, "usedHours": used, "idleHours": idle})

            logger_uid = random.choice(ENG_UIDS)

            weather_opts = ["Sunny", "Cloudy", "Partly Cloudy", "Hot", "Light Rain", "Overcast"]
            is_delay = random.random() < 0.05

            db.collection("projects").document(pid).collection("resourceLogs").document(lid).set({
                "id": lid,
                "projectId": pid,
                "loggedBy": logger_uid,
                "date": log_date,
                "logDate": log_date,
                "materialUsage": daily_usage,
                "equipment": equip_entries,
                "laborHours": round(random.uniform(30, 120), 1),
                "notes": f"Day {i+1} site report. {'Foundation work.' if i < 7 else 'Superstructure progress.' if i < 20 else 'Finishing phase.'}",
                "weatherCondition": random.choice(weather_opts),
                "isWeatherDelay": is_delay,
                "createdAt": log_date + timedelta(hours=random.randint(7, 18)),
            })

        # -- 4. VENDOR BILLS / INVOICES --
        num_bills = max(1, p["days_ago"] // 10)
        for i in range(num_bills):
            bill_id = f"bill_{pid}_{i}"
            bill_date = start_date + timedelta(days=i * 10 + random.randint(3, 8))

            items = []
            chosen_mats = random.sample(MATERIALS, random.randint(2, 4))
            for mat in chosen_mats:
                qty = est_materials[mat]["quantity"] / (num_bills + 1)
                qty *= random.uniform(0.8, 1.2)
                unit_map = {"cement": "bags", "bricks": "nos", "sand": "m3", "steel": "kg", "aggregate": "m3"}
                rate = RATES[mat]
                items.append({
                    "description": f"Bulk {mat} supply - Grade A",
                    "quantity": round(qty, 2),
                    "unit": unit_map.get(mat, "unit"),
                    "rate": round(rate, 2),
                    "amount": round(qty * rate, 2),
                })

            total_amount = sum(item["amount"] for item in items)

            db.collection("projects").document(pid).collection("vendorBills").document(bill_id).set({
                "id": bill_id,
                "projectId": pid,
                "vendorName": random.choice(VENDOR_NAMES),
                "amount": total_amount,
                "date": bill_date,
                "category": "Material Supply",
                "fileUrl": "",
                "uploadedBy": mgr_uid,
                "items": items,
                "createdAt": bill_date,
            })

        # -- 5. DEVIATIONS --
        if p["days_ago"] > 5:
            did = f"dev_{pid}_recent"
            dev_pct = random.uniform(2.5, 8.5)
            severity = "warning" if dev_pct > 5 else "normal"
            if dev_pct > 10:
                severity = "critical"

            dev_breakdown = {}
            for mat in MATERIALS:
                est = est_materials[mat]["quantity"] * (p["days_ago"] / p["duration"])
                act = est * (1 + (dev_pct / 100) * random.uniform(0.5, 1.5))
                dev_breakdown[mat] = {
                    "estimated": round(est, 2),
                    "actual": round(act, 2),
                    "deviationPct": round(((act - est) / est) * 100, 1) if est > 0 else 0,
                }

            db.collection("projects").document(pid).collection("deviations").document(did).set({
                "deviationId": did,
                "projectId": pid,
                "generatedAt": today - timedelta(minutes=30),
                "overallSeverity": severity,
                "deviations": dev_breakdown,
                "reason": f"Detected {dev_pct:.1f}% material overrun in recent logs.",
                "mlOverrunProbability": round(dev_pct / 100.0, 4),
                "aiInsight": "Review vendor bills for potential price hikes or wastage on site.",
            })

        # -- 6. DELAY NOTICES --
        if p["status"] == "active":
            eng1_uid = ENG_UIDS[0]
            eng2_uid = ENG_UIDS[1]
            eng1_name = ENGINEERS[eng1_uid]
            eng2_name = ENGINEERS[eng2_uid]

            dn_id = f"dn_{pid}_1"
            db.collection("projects").document(pid).collection("delayNotices").document(dn_id).set({
                "id": dn_id,
                "projectId": pid,
                "type": "material_delivery",
                "title": "Shortage of OPC Cement",
                "description": "The local supplier is facing logistics issues due to transport strike in the region.",
                "affectedMaterials": ["cement"],
                "expectedDeliveryDate": today + timedelta(days=5),
                "reportedDate": today - timedelta(days=1),
                "createdBy": eng1_uid,
                "createdByName": eng1_name,
                "status": "pending_consensus",
                "requiredVoters": [eng2_uid],
                "votes": {
                    eng1_uid: {
                        "vote": "agree",
                        "comment": "Material supply is indeed slow.",
                        "votedAt": today - timedelta(days=1),
                        "engineerName": eng1_name,
                    }
                },
            })

            dn_id_app = f"dn_{pid}_app"
            db.collection("projects").document(pid).collection("delayNotices").document(dn_id_app).set({
                "id": dn_id_app,
                "projectId": pid,
                "type": "equipment",
                "title": "Excavator Maintenance Delay",
                "description": "Hydraulic part replacement taking longer than expected from supplier.",
                "affectedMaterials": [],
                "expectedDeliveryDate": today + timedelta(days=2),
                "reportedDate": today - timedelta(days=3),
                "createdBy": eng2_uid,
                "createdByName": eng2_name,
                "status": "approved",
                "requiredVoters": [eng1_uid],
                "votes": {
                    eng1_uid: {
                        "vote": "agree",
                        "comment": "Verified on site. Part is backordered.",
                        "votedAt": today - timedelta(days=2),
                        "engineerName": eng1_name,
                    },
                    eng2_uid: {
                        "vote": "agree",
                        "comment": "Crucial for next phase of excavation.",
                        "votedAt": today - timedelta(days=2),
                        "engineerName": eng2_name,
                    },
                },
                "consensusAt": today - timedelta(days=2),
            })

        print(f"            Logs: {num_logs} | Invoices: {num_bills} | Deviations: {'Yes' if p['days_ago'] > 5 else 'No'}")
        print()

    print("=" * 50)
    print("Seeding complete for all 10 projects.")
    print(f"Managers used: {len(MANAGERS)}")
    print(f"Engineers used: {len(ENGINEERS)}")
    print("=" * 50)


if __name__ == "__main__":
    delete_all_projects()
    seed_data()
