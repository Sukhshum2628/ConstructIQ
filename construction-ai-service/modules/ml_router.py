from fastapi import APIRouter, HTTPException, Depends
from .api_models import PredictionRequest
from .ml_predictor import predict_overrun
from .auth_middleware import verify_firebase_token

router = APIRouter()

@router.post("/predict-overrun", dependencies=[Depends(verify_firebase_token)])
async def predict_overrun_endpoint(req: PredictionRequest):
    """Predict project cost/time overrun probability."""
    try:
        type_map = {"Residential": 0, "Commercial": 1, "Infrastructure": 2}
        type_encoded = type_map.get(req.project_type, 0)
        
        data = {
            "material_deviation_avg": req.material_deviation_avg,
            "equipment_idle_ratio": req.equipment_idle_ratio,
            "days_elapsed_pct": req.days_elapsed_pct,
            "budget_size": req.budget_size,
            "project_type_encoded": type_encoded
        }
        
        # Pass projectId so predictions are cached per project and only
        # recomputed when the input features actually change.
        probability = predict_overrun(data, project_id=req.projectId)
        
        return {
            "projectId": req.projectId,
            "mlOverrunProbability": probability, 
            "riskLevel": "High" if probability > 0.6 else "Medium" if probability > 0.3 else "Low"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
