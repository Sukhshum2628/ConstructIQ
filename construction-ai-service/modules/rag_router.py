from fastapi import APIRouter, HTTPException, Depends
from .api_models import ChatRequest, IndexRequest
from .rag_engine import rag_engine
from .auth_middleware import verify_firebase_token

router = APIRouter()

@router.post("/query", dependencies=[Depends(verify_firebase_token)])
async def ai_query_endpoint(req: ChatRequest):
    """Context-aware AI assistant query."""
    try:
        answer = rag_engine.get_answer(req.projectId, req.message)
        return {"reply": answer}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/index", dependencies=[Depends(verify_firebase_token)])
async def index_project_endpoint(req: IndexRequest):
    """Index project data for RAG assistant."""
    try:
        if os.getenv("RENDER_EXTERNAL_URL"):
            return {"status": "indexed_skipped_low_ram", "chunks_indexed": 0}
        count = rag_engine.index_project_data(req.projectId)
        return {"status": "indexed", "chunks_indexed": count}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
