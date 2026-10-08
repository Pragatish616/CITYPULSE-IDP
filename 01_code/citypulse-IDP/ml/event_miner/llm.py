"""A small client for a local Ollama server (ADR-030). Nothing here leaves the machine: the default address is 127.0.0.1.

Settings (environment): OLLAMA_URL (default http://127.0.0.1:11434), MINER_MODEL (default qwen3.5:0.8b),
MINER_EMBED_MODEL (default nomic-embed-text).
"""

from __future__ import annotations

import json
import os
from typing import Any

import httpx

DEFAULT_URL = "http://127.0.0.1:11434"
DEFAULT_MODEL = "qwen3.5:0.8b"
DEFAULT_EMBED_MODEL = "nomic-embed-text"
SEED = 20260918


class LLMError(Exception):
    """The model server could not be reached or gave an answer that is not the JSON asked for."""


class OllamaClient:
    def __init__(
        self,
        base_url: str | None = None,
        model: str | None = None,
        embed_model: str | None = None,
        timeout: float = 180.0,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.base_url = (base_url or os.environ.get("OLLAMA_URL") or DEFAULT_URL).rstrip("/")
        self.model = model or os.environ.get("MINER_MODEL") or DEFAULT_MODEL
        self.embed_model = embed_model or os.environ.get("MINER_EMBED_MODEL") or DEFAULT_EMBED_MODEL
        self._http = httpx.Client(base_url=self.base_url, timeout=timeout, transport=transport)

    def close(self) -> None:
        self._http.close()

    def _post(self, path: str, body: dict[str, Any]) -> dict[str, Any]:
        try:
            r = self._http.post(path, json=body)
        except httpx.HTTPError as exc:
            raise LLMError(f"cannot reach Ollama at {self.base_url}: {exc!r}") from exc
        if r.status_code != 200:
            raise LLMError(f"Ollama {path} returned {r.status_code}: {r.text[:200]}")
        try:
            return r.json()
        except ValueError as exc:
            raise LLMError(f"Ollama {path} did not return JSON") from exc

    def chat_json(self, system: str, user: str, schema: dict[str, Any], num_ctx: int = 8192) -> dict[str, Any]:
        """One deterministic call whose answer must be JSON in `schema` (Ollama structured output). Thinking is off."""
        reply = self._post(
            "/api/chat",
            {
                "model": self.model,
                "stream": False,
                "think": False,
                "format": schema,
                "options": {"temperature": 0, "seed": SEED, "num_ctx": num_ctx},
                "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            },
        )
        content = (reply.get("message") or {}).get("content")
        if not isinstance(content, str):
            raise LLMError("the reply has no message content")
        try:
            out = json.loads(content)
        except ValueError as exc:
            raise LLMError(f"the model did not answer JSON: {content[:200]!r}") from exc
        if not isinstance(out, dict):
            raise LLMError("the model's JSON is not an object")
        return out

    def embed(self, texts: list[str]) -> list[list[float]]:
        reply = self._post("/api/embed", {"model": self.embed_model, "input": texts})
        vectors = reply.get("embeddings")
        if not isinstance(vectors, list) or len(vectors) != len(texts):
            raise LLMError("the embedding reply does not hold one vector per text")
        return vectors

    def digest(self, model: str) -> str | None:
        """The local digest of `model`, recorded with every output so a result names the exact weights used."""
        # A name without a tag means `:latest`, as Ollama itself reads it.
        wanted = {model, model if ":" in model else f"{model}:latest"}
        try:
            r = self._http.get("/api/tags")
            r.raise_for_status()
            for m in r.json().get("models", []):
                if m.get("name") in wanted or m.get("model") in wanted:
                    return m.get("digest")
        except (httpx.HTTPError, ValueError):
            return None
        return None
