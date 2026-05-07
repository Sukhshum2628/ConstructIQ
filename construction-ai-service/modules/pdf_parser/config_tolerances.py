"""
Global Geometric Tolerances for the PDF Parsing Pipeline.

Centralizing these values prevents tolerance drift and ensures that
all phases (centerline reconstruction, topology building, semantic classification)
use the exact same physical rules.
"""

GEOMETRIC_TOLERANCES = {
    # 1. Line Connectivity
    "endpoint_snap_m": 0.05,       # Merge line endpoints if gap < 50mm
    "collinear_merge_gap_m": 0.1,  # Collapse collinear segments if gap < 100mm
    "parallel_angle_deg": 2.0,     # Treat lines as parallel if angle diff < 2 degrees
    
    # 2. Wall Detection
    "min_wall_thickness_m": 0.05,  # 50mm (e.g., thin partition)
    "max_wall_thickness_m": 0.40,  # 400mm (e.g., thick external load-bearing wall)
    "min_wall_length_m": 0.20,     # Ignore walls shorter than 200mm
    
    # 3. Room & Polygon Topology
    "min_room_area_sqm": 1.0,      # Reject enclosed spaces < 1m² (likely a duct or noise)
    
    # 4. Openings (Doors/Windows)
    "max_door_width_m": 2.5,       # Sanity check: doors wider than 2.5m are flagged
    "min_door_width_m": 0.6,       # Sanity check: doors narrower than 600mm are flagged
    "opening_snap_to_wall_m": 0.2  # Snap a door to a wall if within 200mm
}
