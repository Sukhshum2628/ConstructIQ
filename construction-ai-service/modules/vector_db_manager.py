import os
import chromadb
from chromadb.api.types import Documents, EmbeddingFunction, Embeddings
from openai import OpenAI


class NimEmbeddingFunction(EmbeddingFunction):
    """ChromaDB embedding function backed by NVIDIA NIM's hosted embedding API.

    Replaces the local `sentence-transformers` (PyTorch) model, which alone
    consumed ~400-700MB of RAM and made the service exceed Render's 512MB free
    tier. NIM is reached through the same OpenAI-compatible endpoint and API key
    already used for chat, so no extra subscription is required.
    """

    # NIM caps how many inputs it will embed per request; stay well under it.
    _BATCH = 50

    def __init__(self, model: str | None = None, input_type: str = "passage"):
        self._model = model or os.getenv("NVIDIA_EMBED_MODEL", "baai/bge-m3")
        self._input_type = input_type
        self._client = None

    def _get_client(self) -> OpenAI:
        # Built lazily so the collection can be created without NVIDIA_API_KEY;
        # the key is only required when documents are actually embedded.
        if self._client is None:
            self._client = OpenAI(
                base_url=os.getenv("NVIDIA_BASE_URL",
                                   "https://integrate.api.nvidia.com/v1"),
                api_key=os.getenv("NVIDIA_API_KEY"),
            )
        return self._client

    def _embed(self, texts: list) -> list:
        client = self._get_client()
        # NVIDIA embedding NIMs want input_type/truncate via extra_body; some
        # OpenAI-style models reject extra args, so fall back without them.
        try:
            resp = client.embeddings.create(
                model=self._model,
                input=texts,
                encoding_format="float",
                extra_body={"input_type": self._input_type, "truncate": "END"},
            )
        except TypeError:
            resp = client.embeddings.create(
                model=self._model, input=texts, encoding_format="float")
        return [d.embedding for d in resp.data]

    def __call__(self, input: Documents) -> Embeddings:
        # ChromaDB may pass empty strings; the API rejects those.
        texts = [t if (t and t.strip()) else " " for t in input]
        out: list = []
        for i in range(0, len(texts), self._BATCH):
            out.extend(self._embed(texts[i:i + self._BATCH]))
        return out


class VectorDBManager:
    def __init__(self, persist_directory="./chroma_db"):
        self.persist_directory = persist_directory
        self._client = None
        self._embedding_fn = None
        self._collection = None

    @property
    def client(self):
        if self._client is None:
            self._client = chromadb.PersistentClient(path=self.persist_directory)
        return self._client

    @property
    def embedding_fn(self):
        if self._embedding_fn is None:
            # Lightweight: just an HTTP client to NIM — no model weights in RAM.
            self._embedding_fn = NimEmbeddingFunction()
        return self._embedding_fn

    @property
    def collection(self):
        if self._collection is None:
            self._collection = self.client.get_or_create_collection(
                name="construction_knowledge",
                embedding_function=self.embedding_fn
            )
        return self._collection

    def add_documents(self, documents: list, metadatas: list, ids: list):
        self.collection.add(
            documents=documents,
            metadatas=metadatas,
            ids=ids
        )

    def query(self, query_text: str, n_results: int = 3):
        return self.collection.query(
            query_texts=[query_text],
            n_results=n_results
        )

# Global singleton accessor
_manager_instance = None

def get_db_manager():
    global _manager_instance
    if _manager_instance is None:
        _manager_instance = VectorDBManager()
    return _manager_instance
