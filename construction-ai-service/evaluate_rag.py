"""
RAGAS evaluation harness for the ConstructIQ RAG pipeline.

Measures the four core RAGAS metrics on a curated test set:
  - faithfulness        : is the answer grounded in the retrieved context?
  - answer_relevancy    : does the answer actually address the question?
  - context_precision   : are the retrieved chunks relevant (signal/noise)?
  - context_recall      : did retrieval surface what's needed for the truth?

It uses your existing NVIDIA NIM endpoint as BOTH the answer generator (via the
real RAGEngine) and the RAGAS judge LLM/embeddings, so no OpenAI key is needed.

Run:
    pip install -r requirements-eval.txt
    set NVIDIA_API_KEY=...            # plus Firebase creds, or it uses MOCK data
    python evaluate_rag.py --project_id <REAL_PROJECT_ID>

Edit TEST_SET below with questions + ground-truth answers for a project that has
real data (estimates, logs, deviations) for meaningful numbers. With no Firestore
it still runs against the RAGEngine MOCK data so you can smoke-test the harness.
"""

import os
import argparse

from modules.rag_engine import rag_engine
from modules.vector_db_manager import get_db_manager

# --- Curated evaluation set ---------------------------------------------------
# Ground truths are short reference answers a domain expert would give. Replace
# these with the truth for YOUR test project for accurate context_recall.
TEST_SET = [
    {
        "question": "Is the project currently over budget or on track?",
        "ground_truth": "The project status is driven by the deviation severity and "
                        "the gap between the CAD estimated cost and the invoiced spend "
                        "to date, judged against the elapsed timeline.",
    },
    {
        "question": "Which material has the largest cost deviation?",
        "ground_truth": "The material with the highest deviation percentage versus its "
                        "pro-rated planned quantity in the deviation breakdown.",
    },
    {
        "question": "What is the ML-predicted overrun probability for this project?",
        "ground_truth": "The XGBoost overrun probability reported in the real-time "
                        "deviation metrics section.",
    },
    {
        "question": "Summarise recent material consumption on site.",
        "ground_truth": "A summary of the most recent resource logs and the quantities "
                        "of materials consumed.",
    },
    {
        "question": "How much of the project timeline has elapsed so far?",
        "ground_truth": "The number of elapsed days out of the total project duration, "
                        "expressed as a percentage of the timeline.",
    },
    {
        "question": "What is the total amount invoiced by vendors to date?",
        "ground_truth": "The sum of all vendor bill amounts recorded for the project.",
    },
]


def retrieve_contexts(project_id: str, question: str, k: int = 8):
    """Pull the chunks the RAG retriever would use for this question."""
    dbm = get_db_manager()
    col = dbm.client.get_or_create_collection(
        name=f"project_{project_id}", embedding_function=dbm.embedding_fn
    )
    res = col.query(query_texts=[question], n_results=k)
    return (res.get("documents") or [[]])[0]


def build_samples(project_id: str):
    rag_engine._ensure_indexed(project_id)  # make sure the collection exists
    samples = []
    for item in TEST_SET:
        q = item["question"]
        contexts = retrieve_contexts(project_id, q)
        answer = rag_engine.get_answer(project_id, q)
        samples.append({
            "question": q,
            "answer": answer,
            "contexts": contexts if contexts else ["(no context retrieved)"],
            "ground_truth": item["ground_truth"],
        })
        print(f"  ✓ {q[:60]}…  ({len(contexts)} chunks)")
    return samples


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project_id", default="eval_demo",
                    help="Project id with real data; defaults to MOCK demo data.")
    ap.add_argument("--out", default="rag_eval_results.csv")
    args = ap.parse_args()

    if not os.getenv("NVIDIA_API_KEY"):
        raise SystemExit("Set NVIDIA_API_KEY first (used for generation + judging).")

    print(f"Building samples for project '{args.project_id}'…")
    samples = build_samples(args.project_id)

    # Lazy imports so the file is importable without the eval deps installed.
    from datasets import Dataset
    from langchain_openai import ChatOpenAI, OpenAIEmbeddings
    from ragas import evaluate
    from ragas.llms import LangchainLLMWrapper
    from ragas.embeddings import LangchainEmbeddingsWrapper
    from ragas.metrics import (faithfulness, answer_relevancy,
                               context_precision, context_recall)

    base_url = os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1")
    key = os.getenv("NVIDIA_API_KEY")
    judge_llm = LangchainLLMWrapper(ChatOpenAI(
        base_url=base_url, api_key=key,
        model=os.getenv("NVIDIA_MODEL", "meta/llama-3.1-8b-instruct"),
        temperature=0.0))
    judge_emb = LangchainEmbeddingsWrapper(OpenAIEmbeddings(
        base_url=base_url, api_key=key,
        model=os.getenv("NVIDIA_EMBED_MODEL", "baai/bge-m3")))

    ds = Dataset.from_list(samples)
    print("\nRunning RAGAS evaluation (this calls the judge LLM per sample)…")
    result = evaluate(
        ds,
        metrics=[faithfulness, answer_relevancy, context_precision, context_recall],
        llm=judge_llm,
        embeddings=judge_emb,
    )
    print("\n===== RAGAS RESULTS =====")
    print(result)
    try:
        df = result.to_pandas()
        df.to_csv(args.out, index=False)
        print(f"\nPer-question scores saved to {args.out}")
        print("\nMean scores:")
        for col in ["faithfulness", "answer_relevancy",
                    "context_precision", "context_recall"]:
            if col in df:
                print(f"  {col:18s}: {df[col].mean():.3f}")
    except Exception as e:
        print(f"(Could not write CSV: {e})")


if __name__ == "__main__":
    main()
