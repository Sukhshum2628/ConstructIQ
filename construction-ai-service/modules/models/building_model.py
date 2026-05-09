import json
import os
from typing import List, Dict, Any, Optional

class IntermediateBuildingModel:
    """
    The canonical contract for every phase of the PDF parser.
    This serves as the single source of truth for the entire pipeline.
    """
    
    def __init__(self):
        # 1. Metadata & Lineage
        self.metadata = {
            "source_file": "",
            "document_type": "unknown",       # e.g., 'architectural', 'structural'
            "vector_threshold_passed": False,
            "scale_confidence": 0.0,
            "topology_confidence": 0.0,
            "phase_timing_ms": {}             # e.g., {"phase_4": 120}
        }
        
        # 2. Global Document Properties
        self.scale_multiplier = 1.0           # Default 1.0 until calibrated
        self.unit_system = "metric"           # 'metric' or 'imperial'
        
        # 3. Structural Topology (Organized by Floor)
        self.floors: List[Dict[str, Any]] = []
        
    def add_floor(self, level_name: str) -> Dict[str, Any]:
        """Initializes a new floor object in the topology."""
        floor = {
            "level": level_name,
            "outer_boundary": {"area": 0.0, "polygon": []},
            "walls": [],
            "rooms": [],
            "doors": [],
            "windows": []
        }
        self.floors.append(floor)
        return floor
        
    def log_timing(self, phase_name: str, duration_ms: int):
        """Records execution time for performance tracking."""
        self.metadata["phase_timing_ms"][phase_name] = duration_ms

    def to_dict(self) -> Dict[str, Any]:
        return {
            "metadata": self.metadata,
            "scale_multiplier": self.scale_multiplier,
            "unit_system": self.unit_system,
            "floors": self.floors
        }
        
    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2)
        
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "IntermediateBuildingModel":
        model = cls()
        model.metadata = data.get("metadata", model.metadata)
        model.scale_multiplier = data.get("scale_multiplier", 1.0)
        model.unit_system = data.get("unit_system", "metric")
        model.floors = data.get("floors", [])
        return model
