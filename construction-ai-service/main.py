import os
import uvicorn
import asyncio
import httpx
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import ezdxf
from contextlib import asynccontextmanager
from modules import cad_router, estimation_router, deviation_router, ml_router, rag_router, agent_router
from modules.invoice_parser import parse_invoice_pdf

async def self_ping_loop():
    """
    Self-pinging background task to keep the Render free tier service online.
    Pings `${RENDER_EXTERNAL_URL}/health` every 14 minutes to prevent container sleep.
    """
    # Wait for server to fully bind and start before initial ping
    await asyncio.sleep(15)
    external_url = os.getenv("RENDER_EXTERNAL_URL")
    
    if not external_url:
        print("Self-ping: RENDER_EXTERNAL_URL not found in env. Self-pinging disabled.")
        return
        
    print(f"Self-ping: Starting background loop. Target: {external_url}/health")
    async with httpx.AsyncClient() as client:
        while True:
            try:
                # Remove trailing slashes and append health endpoint
                url = f"{external_url.rstrip('/')}/health"
                response = await client.get(url, timeout=15.0)
                print(f"Self-ping: Health check ping successful. Status: {response.status_code}")
            except Exception as e:
                print(f"Self-ping: Error sending health check ping: {e}")
            
            # Sleep for 2 minutes (120 seconds) as requested to keep render active
            await asyncio.sleep(120)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Model checks/loading on startup
    if os.path.exists("models/cost_overrun_model.pkl"):
        print("ML Model detected.")
        
    print("Postponing heavy imports (RAG/Embeddings) for lazy execution to save RAM...")
    
    # Start self-pinging background task to bypass Render free tier sleep timeout
    ping_task = asyncio.create_task(self_ping_loop())
    
    print("Startup complete. Minimal footprint.")
    yield
    
    # Cancel self-ping task cleanly on shutdown
    ping_task.cancel()
    try:
        await ping_task
    except asyncio.CancelledError:
        pass

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
app.include_router(agent_router.router, prefix="/api/agent", tags=["Agent"])

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "ConstructIQ AI Service",
        "version": "1.0.0"
    }

@app.post("/parse-invoice")
async def parse_invoice(file: UploadFile = File(...)):
    """
    Parse an uploaded invoice PDF and extract structured data.
    Uses pdfplumber (no API key needed) with OCR fallback.
    Returns vendor name, line items, and grand total.
    """
    if not file.filename.lower().endswith(('.pdf', '.jpg', '.jpeg', '.png')):
        raise HTTPException(
            status_code=400,
            detail='Unsupported file type. Upload PDF, JPG, or PNG.'
        )

    contents = await file.read()

    # For images (JPG/PNG), wrap in a minimal PDF context for pytesseract
    if file.filename.lower().endswith(('.jpg', '.jpeg', '.png')):
        try:
            import pytesseract
            from PIL import Image
            import io as _io
            img = Image.open(_io.BytesIO(contents))
            text = pytesseract.image_to_string(img, lang='eng')
            # Re-use parse logic by injecting text directly
            from modules.invoice_parser import (
                _extract_vendor_name, _extract_invoice_number,
                _extract_grand_total, _extract_line_items
            )
            result = {
                'success': True,
                'vendorName':    _extract_vendor_name(text),
                'invoiceNumber': _extract_invoice_number(text),
                'lineItems':     _extract_line_items(text),
                'grandTotal':    _extract_grand_total(text),
                'extractionMethod': 'ocr-image',
                'rawTextPreview': text[:300],
                'warnings': [],
            }
        except Exception as e:
            result = {
                'success': False,
                'warnings': [f'Image parsing failed: {str(e)}']
            }
    else:
        result = parse_invoice_pdf(contents)

    return result

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    uvicorn.run("main:app", host="0.0.0.0", port=port, reload=False)
