"""
/api/agent — the stateful Construction Project Analyst agent.

Kept separate from /api/rag: RAG answers from retrieved text, while this agent
actively decides which project tools to call (schedule, cost, logs, weather)
and synthesises a multi-source answer with recommendations.
"""

import traceback

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from modules.auth_middleware import verify_firebase_token, check_project_membership

router = APIRouter()


class AgentRequest(BaseModel):
    project_id: str
    question: str


@router.post("/analyze")
async def analyze(req: AgentRequest, user: dict = Depends(verify_firebase_token)):
    if not req.project_id or not req.question.strip():
        raise HTTPException(status_code=400, detail="project_id and question are required.")
    
    # IDOR Check: Ensure authenticated user is authorized for this project
    await check_project_membership(user.get("uid", ""), req.project_id)
    try:
        # Lazy import so langgraph/langchain only load when the agent is used,
        # keeping server startup under the 512MB Render tier.
        from modules.agent.agent_graph import run_agent

        # run_agent is async: the graph fans out the four independent tools
        # concurrently, so we await it directly on the event loop.
        result = await run_agent(req.project_id, req.question)
        return {"success": True, **result}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Agent failed: {e}")
