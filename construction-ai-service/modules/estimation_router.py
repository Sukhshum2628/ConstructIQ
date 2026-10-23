from fastapi import APIRouter, HTTPException, Depends, UploadFile, File, Response
from .api_models import EstimationRequest, ReportRequest
from .estimation_engine import calculate_materials, calculate_labour
from .report_generator import generate_estimation_report
from .auth_middleware import verify_firebase_token
from .invoice_parser import parse_invoice_pdf

router = APIRouter()

@router.post("/estimate", dependencies=[Depends(verify_firebase_token)])
async def estimate_materials_endpoint(req: EstimationRequest):
    """Calculate materials and labour based on geometry."""
    try:
        materials = calculate_materials(req.geometry)
        labour = calculate_labour(materials, req.geometry)
        total_labour_days = sum(l["labour_days"] for l in labour.values())
        
        return {
            "projectId": req.projectId,
            "materials": materials,
            "labour": labour,
            "total_labour_days": total_labour_days,
            "confidence": "high"
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/extract-budget", dependencies=[Depends(verify_firebase_token)])
async def extract_invoice_budget(file: UploadFile = File(...)):
    """Extract budget from PDF invoice using local parser."""
    try:
        content = await file.read()
        result = parse_invoice_pdf(content)
        return {
            "extracted_budget": result.get("grandTotal", 0.0),
            "confidence": 0.85 if result.get("success") else 0.0
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/extract-items", dependencies=[Depends(verify_firebase_token)])
async def extract_items_endpoint(file: UploadFile = File(...)):
    """Extract itemized details from PDF invoice using local parser."""
    try:
        content = await file.read()
        result = parse_invoice_pdf(content)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/generate-report", dependencies=[Depends(verify_firebase_token)])
async def generate_report_endpoint(data: ReportRequest):
    """Generate high-fidelity PDF estimation report."""
    try:
        pdf_bytes = generate_estimation_report(
            project_name=data.project_name,
            geometry=data.geometry,
            materials=data.materials,
            labour=data.labour
        )
        return Response(
            content=pdf_bytes,
            media_type="application/pdf",
            headers={"Content-Disposition": f"attachment; filename=Estimation_{data.project_name}.pdf"}
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
