"""
LangGraph Construction Project Analyst agent.

A stateful ReAct agent: given a question it decides which project tools to call
(milestones, cost/deviation, logs, weather), gathers the data across multiple
sources, and synthesises one multi-source answer with recommendations — the
thing plain RAG can't do.

Heavy imports (langgraph / langchain_openai) live here, not in main.py, and the
router imports this module lazily, so server startup stays light on Render's
512MB tier.
"""

import os
from functools import lru_cache

from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent

from modules.agent.tools import make_tools

SYSTEM_PROMPT = (
    "You are the ConstructIQ Project Analyst, an expert construction project "
    "manager. Answer the user's question about the current project by CALLING "
    "THE AVAILABLE TOOLS to gather real data — never invent numbers. "
    "For 'is the project on track' or health questions, check the schedule, the "
    "cost/deviation, and recent logs before answering. "
    "Then give a concise, professional answer that: (1) states the overall "
    "verdict, (2) cites the specific numbers from the tools, (3) ends with 1-3 "
    "concrete recommendations. Keep it under ~180 words."
)


@lru_cache(maxsize=1)
def _model() -> ChatOpenAI:
    # Same NVIDIA NIM endpoint the RAG engine uses (OpenAI-compatible). A larger
    # model can be set via NVIDIA_AGENT_MODEL for more reliable tool-calling.
    return ChatOpenAI(
        base_url=os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1"),
        api_key=os.getenv("NVIDIA_API_KEY"),
        model=os.getenv("NVIDIA_AGENT_MODEL",
                        os.getenv("NVIDIA_MODEL", "meta/llama-3.1-8b-instruct")),
        temperature=0.2,
        max_tokens=1024,
    )


def run_agent(project_id: str, question: str) -> dict:
    """Run the analyst agent for one project/question. Returns the synthesised
    answer plus which tools were used (handy for debugging the agent's path)."""
    agent = create_react_agent(_model(), make_tools(project_id))
    result = agent.invoke(
        {"messages": [("system", SYSTEM_PROMPT), ("user", question)]},
        config={"recursion_limit": 8},
    )
    messages = result["messages"]
    answer = messages[-1].content if messages else ""
    tools_used = [getattr(m, "name", "") for m in messages
                  if getattr(m, "type", "") == "tool"]
    return {"answer": answer, "tools_used": tools_used}
