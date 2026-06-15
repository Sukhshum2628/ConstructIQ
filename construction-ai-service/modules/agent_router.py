"""
/api/agent — the stateful Construction Project Analyst agent.

Kept separate from /api/rag: RAG answers from retrieved text, while this agent
actively decides which project tools to call (schedule, cost, logs, weather)
and synthesises a multi-source answer with recommendations.
"""

import asyncio
import traceback

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()


class AgentRequest(BaseModel):
    project_id: str
    question: str


@router.post("/analyze")
async def analyze(req: AgentRequest):
    if not req.project_id or not req.question.strip():
        raise HTTPException(status_code=400, detail="project_id and question are required.")
    try:
        # Lazy import so langgraph/langchain only load when the agent is used,
        # keeping server startup under the 512MB Render tier.
        from modules.agent.agent_graph import run_agent

        # run_agent is sync (langgraph .invoke); run it off the event loop.
        result = await asyncio.to_thread(run_agent, req.project_id, req.question)
        return {"success": True, **result}
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Agent failed: {e}")
