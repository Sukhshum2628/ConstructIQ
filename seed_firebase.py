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

    # Totals with 20% wastage/finishing factor
    total_cement = (cement_masonry + cement_slab + cement_stair +
                    cement_beam + cement_col + cement_plaster + cement_screed) * 1.4
    total_sand = (sand_masonry + sand_slab + sand_plaster + sand_screed) * 1.3
    total_aggregate = (aggregate_slab + aggregate_stair + aggregate_beam + aggregate_col) * 1.3
    total_steel = (steel_slab + steel_beam + steel_col) * 1.25

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
    "cement":    440.0,
    "bricks":    18.0,
    "steel":     92.0,
    "sand":      2800.0,
    "aggregate": 3200.0,
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
        "id": "jammu_heights",
        "name": "Jammu Heights Luxury Apartments",
        "location": "Sector 12, Jammu",
        "status": "active",
        "log_days": 3,
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
        "id": "gandhi_nagar_villas",
        "name": "Gandhi Nagar Royal Villas",
        "location": "Gandhi Nagar, Jammu",
        "status": "active",
        "log_days": 5,
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
        "id": "techpark_phase1",
        "name": "TechPark Phase 1",
        "location": "Rehari Colony, Jammu",
        "status": "active",
        "log_days": 45,
        "duration": 200,
        "manager": MGR_UIDS[1],
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
        "id": "riverside_commercial",
        "name": "Riverside Commercial",
        "location": "Channi Himmat, Jammu",
        "status": "active",
        "log_days": 55,
        "duration": 180,
        "manager": MGR_UIDS[1],
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
        "id": "greenfield_villas",
        "name": "Greenfield Villas",
        "location": "Trikuta Nagar, Jammu",
        "status": "active",
        "log_days": 120,
        "duration": 270,
        "manager": MGR_UIDS[2],
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
        "id": "metro_station_annex",
        "name": "Metro Station Annex",
        "location": "Bakshi Nagar, Jammu",
        "status": "active",
        "log_days": 130,
        "duration": 300,
        "manager": MGR_UIDS[2],
        "geo": {
            "totalWallLength": 150.0,
            "totalFloorArea": 350.0,
            "floorCount": 2,
            "doorCount": 12,
            "windowCount": 10,
            "beamLength": 80.0,
            "totalColumnCount": 24,
            "stairArea": 15.0,
        },
    },
    {
        "id": "heritage_hotel_renovation",
        "name": "Heritage Hotel Renovation",
        "location": "Janipur, Jammu",
        "status": "completed",
        "log_days": 148,
        "duration": 150,
        "manager": MGR_UIDS[3],
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
        "id": "city_mall_extension",
        "name": "City Mall Extension",
        "location": "Patnitop Road, Udhampur",
        "status": "completed",
        "log_days": 178,
        "duration": 180,
        "manager": MGR_UIDS[3],
        "geo": {
            "totalWallLength": 95.0,
            "totalFloorArea": 180.0,
            "floorCount": 3,
            "doorCount": 15,
            "windowCount": 12,
            "beamLength": 70.0,
            "totalColumnCount": 16,
            "stairArea": 12.0,
        },
    },
    {
        "id": "kashmir_sports_complex",
        "name": "Kashmir Sports Complex",
        "location": "Kunjwani, Jammu",
        "status": "active",
        "log_days": 60,
        "duration": 200,
        "manager": MGR_UIDS[4],
        "geo": {
            "totalWallLength": 120.0,
            "totalFloorArea": 400.0,
            "floorCount": 1,
            "doorCount": 8,
            "windowCount": 20,
            "beamLength": 150.0,
            "totalColumnCount": 32,
            "stairArea": 0,
        },
    },
    {
        "id": "highway_overpass_bridge",
        "name": "Highway Overpass Bridge",
        "location": "Nanak Nagar, Jammu",
        "status": "active",
        "log_days": 90,
        "duration": 250,
        "manager": MGR_UIDS[4],
        "geo": {
            "totalWallLength": 40.0,
            "totalFloorArea": 200.0,
            "floorCount": 1,
            "doorCount": 0,
            "windowCount": 0,
            "beamLength": 200.0,
            "totalColumnCount": 12,
            "stairArea": 0,
        },
    },
]


# ==================================================
# BIAS & USAGE GENERATOR
# ==================================================
PROJECT_BIAS = {
    # (cement_mult, bricks_mult, steel_mult)
    # >1.0 = over-consuming, <1.0 = under-consuming
    "sunrise_residency":          (1.0,  1.0,  1.0),   # normal, just started
    "valley_view_apartments":     (0.88, 0.92, 0.95),  # slightly under = normal
    "techpark_phase1":            (1.22, 1.18, 1.31),  # over = WARNING
    "riverside_commercial":       (1.35, 1.08, 1.42),  # cement critical, steel high
    "greenfield_villas":          (0.95, 1.02, 0.90),  # mostly normal
    "metro_station_annex":        (1.48, 1.25, 1.55),  # CRITICAL across board
    "heritage_hotel_renovation":  (1.12, 0.98, 1.08),  # mild warning, completed
    "city_mall_extension":        (0.82, 0.88, 0.75),  # under-consumed, completed
    "kashmir_sports_complex":     (1.28, 1.35, 1.20),  # WARNING
    "highway_overpass_bridge":    (1.05, 0.95, 1.18),  # caution on steel
}

def make_material_usage(est_materials, duration, i, proj_id):
    daily_usage = {}
    bias = PROJECT_BIAS.get(proj_id, (1.0, 1.0, 1.0))

    for mat, data in est_materials.items():
        avg = data["quantity"] / duration
        val = avg * random.uniform(0.7, 1.3)
        if i % 7 == 0:
            val *= random.uniform(1.3, 1.6)
        if mat == "steel" and i < 5:
            val *= 2.0  # More steel in early foundation phase
        
        # Internal mapping
        daily_usage[mat] = val

    # Final biased mapping for Firestore keys requested in Fix 2
    mat_out = {}
    mat_out["cement"]       = round(daily_usage.get("cement", 0) * bias[0], 1)
    mat_out["cement_bags"]  = mat_out["cement"]
    mat_out["bricks"]       = round(daily_usage.get("bricks", 0) * bias[1], 1)
    mat_out["brick"]        = mat_out["bricks"]
    mat_out["steel"]        = round(daily_usage.get("steel", 0) * bias[2], 1)
    mat_out["steel_kg"]     = mat_out["steel"]
    mat_out["sand"]         = round(daily_usage.get("sand", 0), 2)
    mat_out["sand_m3"]      = mat_out["sand"]
    mat_out["aggregate"]    = round(daily_usage.get("aggregate", 0), 2)
    mat_out["aggregate_m3"] = mat_out["aggregate"]
    
    return mat_out

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

        start_date = today - timedelta(days=p["log_days"])
        end_date = start_date + timedelta(days=p["duration"])

        # Run the EXACT CPWD estimation engine
        est_materials = cpwd_estimate(geo)

        # Calculate cost using app's material_rates.dart
        material_cost = calc_material_cost(est_materials)
        # 1.6x for Labour(45%) + Markup(15%)
        planned_budget = round(material_cost * 1.6)

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
        for i in range(p["log_days"], 0, -1):
            log_date = today - timedelta(days=i)
            lid = f"log_{pid}_{i}"

            daily_usage = make_material_usage(est_materials, p["duration"], i, pid)

            equip_entries = []
            num_equip = random.randint(1, 3)
            for etype in random.sample(EQUIPMENT_TYPES, num_equip):
                used = round(random.uniform(3, 8), 1)
                idle = round(random.uniform(0.5, 2.5), 1)
                equip_entries.append({"name": etype, "hoursUsed": used, "hoursIdle": idle})

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
                "notes": f"Day {i} site report. {'Foundation work.' if i < 10 else 'Superstructure progress.' if i < 60 else 'Finishing phase.'}",
                "weatherCondition": random.choice(weather_opts),
                "isWeatherDelay": is_delay,
                "createdAt": log_date + timedelta(hours=random.randint(7, 18)),
            })

        # -- 4. VENDOR BILLS / INVOICES --
        num_bills = max(1, p["log_days"] // 10)
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

        # -- 5. DEVIATIONS (Removed: Computed live in-app) --

        # -- 6. DELAY NOTICES --
        if p["status"] == "active" and p["log_days"] > 2:
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

        print(f"            Logs: {p['log_days']} | Invoices: {num_bills} | Deviations: {'Yes' if p['log_days'] > 5 else 'No'}")
        print()

    print("=" * 50)
    print("Seeding complete for all 10 projects.")
    print(f"Managers used: {len(MANAGERS)}")
    print(f"Engineers used: {len(ENGINEERS)}")
    print("=" * 50)


if __name__ == "__main__":
    delete_all_projects()
    seed_data()
