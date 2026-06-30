"""
LangGraph Construction Project Analyst agent.

The four data tools (milestones, cost/deviation, logs, weather) are INDEPENDENT
— each only needs the project_id (bound in its closure) and none consumes
another tool's output — so the graph FANS OUT to all four concurrently (one
LangGraph superstep) and then FANS IN to a single LLM synthesis node. This
replaces the previous sequential ReAct loop, which issued one tool call per LLM
round-trip.

Heavy imports stay here (the router lazy-imports this module) to keep Render
startup light on the 512MB tier. Tool logic itself is unchanged — see tools.py.
"""

import os
from functools import lru_cache
from typing import TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import StateGraph, START, END

from modules.agent.tools import make_tools

SYSTEM_PROMPT = (
    "You are the ConstructIQ Project Analyst, an expert construction project "
    "manager. Using ONLY the project data provided below (already gathered from "
    "the schedule, cost/deviation, recent logs and weather sources), answer the "
    "user's question. Never invent numbers. Give a concise, professional answer "
    "that (1) states the overall verdict, (2) cites the specific numbers, and "
    "(3) ends with 1-3 concrete recommendations. Keep it under ~180 words."
)


class AnalystState(TypedDict, total=False):
    project_id: str
    question: str
    # One key per independent tool, so the parallel branches never write the
    # same field (no reducer needed for the fan-out).
    milestone: str
    cost: str
    logs: str
    weather: str
    answer: str


@lru_cache(maxsize=1)
def _model() -> ChatOpenAI:
    # Same NVIDIA NIM endpoint the RAG engine uses (OpenAI-compatible). A larger
    # model can be set via NVIDIA_AGENT_MODEL.
    return ChatOpenAI(
        base_url=os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1"),
        api_key=os.getenv("NVIDIA_API_KEY"),
        model=os.getenv("NVIDIA_AGENT_MODEL",
                        os.getenv("NVIDIA_MODEL", "meta/llama-3.1-8b-instruct")),
        temperature=0.2,
        max_tokens=1024,
    )


def _build_graph(project_id: str):
    # Tools are unchanged; project_id is bound in their closures (no args).
    tools = {t.name: t for t in make_tools(project_id)}

    async def _run(tool_name: str) -> str:
        # .ainvoke runs the (sync) Firestore tool in a worker thread, so the
        # four nodes' blocking I/O genuinely overlaps. One failing source
        # shouldn't sink the whole answer.
        try:
            return await tools[tool_name].ainvoke({})
        except Exception as e:
            return f"({tool_name} unavailable: {e})"

    async def milestone_node(state): return {"milestone": await _run("get_milestone_status")}
    async def cost_node(state):      return {"cost":      await _run("get_cost_deviation")}
    async def logs_node(state):      return {"logs":      await _run("get_recent_logs")}
    async def weather_node(state):   return {"weather":   await _run("get_weather_impact")}

    async def synthesize_node(state):
        data = (
            f"[Schedule]\n{state.get('milestone', '')}\n\n"
            f"[Cost / Deviation]\n{state.get('cost', '')}\n\n"
            f"[Recent logs]\n{state.get('logs', '')}\n\n"
            f"[Weather]\n{state.get('weather', '')}"
        )
        resp = await _model().ainvoke([
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=f"Question: {state['question']}\n\nProject data:\n{data}"),
        ])
        return {"answer": resp.content}

    g = StateGraph(AnalystState)
    g.add_node("milestone", milestone_node)
    g.add_node("cost", cost_node)
    g.add_node("logs", logs_node)
    g.add_node("weather", weather_node)
    g.add_node("synthesize", synthesize_node)

    # Fan-out: START → all four tool nodes run concurrently in one superstep.
    # Fan-in: each → synthesize, which waits for all four to finish.
    for n in ("milestone", "cost", "logs", "weather"):
        g.add_edge(START, n)
        g.add_edge(n, "synthesize")
    g.add_edge("synthesize", END)
    return g.compile()


async def run_agent(project_id: str, question: str) -> dict:
    """Run the analyst graph: the four independent data tools execute
    concurrently, then a single LLM call synthesises the answer."""
    graph = _build_graph(project_id)
    result = await graph.ainvoke({"project_id": project_id, "question": question})
    return {
        "answer": result.get("answer", ""),
        "tools_used": ["get_milestone_status", "get_cost_deviation",
                       "get_recent_logs", "get_weather_impact"],
    }
