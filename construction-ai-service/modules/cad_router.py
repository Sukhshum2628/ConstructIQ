from fastapi import APIRouter, HTTPException, Depends, UploadFile, File
import traceback
import os
import tempfile
from .api_models import CadParseRequest
from .cad_parser import parse_from_bytes, parse_from_url

from .auth_middleware import verify_firebase_token
from .estimation_engine import calculate_materials, calculate_labour

router = APIRouter()

@router.post("/parse", dependencies=[Depends(verify_firebase_token)])
async def parse_cad(req: CadParseRequest):
    """Parse DXF from a provided URL."""
    try:
        geometry = await parse_from_url(req.file_url)
        return {"projectId": req.projectId, "geometry": geometry}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/parse-upload", dependencies=[Depends(verify_firebase_token)])
async def parse_cad_upload(file: UploadFile = File(...)):
    """Analyze DXF or PDF directly via multipart upload with immediate estimation."""
    try:
        filename = file.filename.lower()
        content = await file.read()
        
        if filename.endswith('.pdf'):
            with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tmp:
                tmp.write(content)
                tmp_path = tmp.name
            
            try:
                try:
                    import fitz
                    from .ml_pdf_parser import parse_pdf_ml
                    from .pdf_parser import parse_pdf_file as parse_pdf_legacy
                except ImportError:
                    # The ML PDF parser (onnxruntime/opencv/PyMuPDF) now runs
                    # on-device in the app, so those heavy libs were dropped from
                    # the server build. DXF is still parsed here (ezdxf).
                    raise HTTPException(
                        status_code=400,
                        detail="PDF geometry parsing runs on-device in the app. "
                               "Upload a DXF for server-side parsing.")

                # Detect if PDF is vector (has embedded text) or raster (scanned image)
                doc = fitz.open(tmp_path)
                page = doc[0]
                word_count = len(page.get_text('words'))
                doc.close()
                
                if word_count > 10:
                    # Vector PDF — use ML pipeline with scale detection
                    result = parse_pdf_ml(tmp_path)
                else:
                    # Raster/Scanned PDF — use legacy parser, flag low confidence
                    result = parse_pdf_legacy(tmp_path)
                    result['confidence'] = min(
                        result.get('confidence', 0.4), 0.3
                    )
                    result['warning'] = (
                        'Scanned PDF detected. Upload DXF for higher accuracy.'
                    )
                
                if "error" in result:
                    if result["error"] == "NO_GEOMETRY":
                        raise HTTPException(status_code=400, detail="PDF does not contain vector geometry. Please upload a CAD-exported PDF.")
                    raise HTTPException(status_code=400, detail=result.get("message", "Error parsing PDF"))
                
                geometry = result
                confidence = result.get("confidence", 0.4)
            finally:
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

        else:
            geometry = parse_from_bytes(content)
            confidence = 0.95

        # Immediate feedback for UI
        from .rag_engine import validate_geometry
        validation = validate_geometry(geometry)
        
        mat_result = calculate_materials(geometry)
        materials = mat_result["materials"]
        labour = calculate_labour(materials, geometry)
        
        return {
            "geometry": geometry,
            "materials": materials,
            "labour": labour,
            "total_labour_days": sum(l["labour_days"] for l in labour.values()),
            "validation": validation,
            "confidence": confidence
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/diag/ai", dependencies=[Depends(verify_firebase_token)])
async def diagnostic_ai():
    """Test AI connectivity with dummy geometry data."""
    try:
        from .rag_engine import validate_geometry
        dummy_geometry = {
            "totalWallLength": 25.5,
            "totalFloorArea": 80.0,
            "wall_lines": [{"start": [0,0], "end": [5,0]}]
        }
        result = validate_geometry(dummy_geometry)
        return {
            "status": "success",
            "test_data": dummy_geometry,
            "ai_response": result
        }
    except Exception as e:
        return {
            "status": "error",
            "message": str(e),
            "traceback": traceback.format_exc()
        }
