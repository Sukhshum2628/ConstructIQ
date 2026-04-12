import os
import uvicorn
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import ezdxf
from contextlib import asynccontextmanager
from modules import cad_router, estimation_router, deviation_router, ml_router, rag_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Model checks/loading on startup
    if os.path.exists("models/cost_overrun_model.pkl"):
        print("ML Model detected.")
    yield

app = FastAPI(
    title="ConstructIQ AI Service",
    description="Modular Advanced Construction Intelligence API",
    version="2.0.0",
    lifespan=lifespan
)

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register Modular Routers
app.include_router(cad_router.router, prefix="/api/cad", tags=["CAD"])
app.include_router(estimation_router.router, prefix="/api/estimation", tags=["Estimation"])
app.include_router(deviation_router.router, prefix="/api/deviation", tags=["Deviation"])
app.include_router(ml_router.router, prefix="/api/ml", tags=["ML"])
app.include_router(rag_router.router, prefix="/api/rag", tags=["RAG"])

@app.get("/health")
async def health_check():
    """System health check."""
    return {
        "status": "operational",
        "environment": "demo" if not os.path.exists("service_account.json") else "production",
        "version": "2.0.0"
    }

@app.post("/parse-cad-upload")
async def parse_cad_upload(file: UploadFile = File(...)):
    """
    Accept DXF file upload directly (multipart/form-data).
    Used during project creation for immediate estimation.
    No Firebase Storage required — file processed in memory.
    """
    try:
        contents = await file.read()
        
        # Import here to avoid circular imports
        from modules.cad_parser import parse_from_bytes
        from modules.estimation_engine import calculate_materials, calculate_labour
        
        geometry = parse_from_bytes(contents)
        mat_result = calculate_materials(geometry)
        labour = calculate_labour(mat_result['materials'], geometry)
        
        return {
            "success": True,
            "filename": file.filename,
            "geometry": geometry,
            "materials": mat_result['materials'],
            "breakdown": mat_result.get('breakdown', {}),
            "zoneBreakdown": mat_result.get('zoneBreakdown', {}),
            "labour": labour,
            "totalLabourDays": sum(
                v.get('labour_days', 0) for v in labour.values()
            ),
            "confidence": geometry['confidence'],
            "disclaimer": (
                "Material quantities estimated using CPWD standard QTO formulas. "
                "Actual requirements may vary based on site conditions and wastage. "
                "No cost figures — obtain vendor quotes separately."
            )
        }
    except ezdxf.DXFStructureError as e:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid or corrupted DXF file: {str(e)}"
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"CAD parsing failed: {str(e)}"
        )

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
