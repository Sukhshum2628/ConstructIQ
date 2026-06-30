import joblib
import hashlib
import pandas as pd
import os

MODEL_PATH = "models/cost_overrun_model.pkl"

# Process-local prediction cache: project_id -> (input_hash, probability).
# ONE slot per project, so a new input hash for a project overwrites (and
# thereby invalidates) that project's previous prediction.
_PREDICTION_CACHE: dict = {}

# The exact features the model depends on. The cache key is a hash of these
# values, so changing any one of them produces a new key and forces a recompute.
_FEATURE_KEYS = (
    "material_deviation_avg",
    "equipment_idle_ratio",
    "days_elapsed_pct",
    "budget_size",
    "project_type_encoded",
)


def _input_hash(data: dict) -> str:
    """Stable hash of the five model inputs. Floats are rounded so negligible
    numerical noise doesn't cause spurious cache misses. This rounded copy is
    used ONLY for the cache key — the original `data` is still what the model
    sees, so feature values passed to inference are unchanged."""
    canon = {k: round(float(data.get(k, 0.0)), 6) for k in _FEATURE_KEYS}
    blob = "|".join(f"{k}={canon[k]}" for k in _FEATURE_KEYS)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def load_model():
    if os.path.exists(MODEL_PATH):
        return joblib.load(MODEL_PATH)
    return None


def predict_overrun(data: dict, project_id: str | None = None) -> float:
    # --- cache layer (around inference only) -------------------------------
    # Reuse the stored prediction when this project's inputs are unchanged.
    key = _input_hash(data)
    if project_id is not None:
        cached = _PREDICTION_CACHE.get(project_id)
        if cached is not None and cached[0] == key:
            return cached[1]  # HIT: identical inputs → skip model load + inference
    # ----------------------------------------------------------------------

    model = load_model()
    if not model:
        return 0.0

    # Input data keys: material_deviation_avg, equipment_idle_ratio,
    # days_elapsed_pct, budget_size, project_type_encoded
    df = pd.DataFrame([data])
    probability = float(model.predict_proba(df)[:, 1][0])

    if project_id is not None:
        # Overwrites any prior entry for this project — that single-slot replace
        # is the cache invalidation for changed inputs.
        _PREDICTION_CACHE[project_id] = (key, probability)
    return probability
