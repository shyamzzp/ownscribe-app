"""Attach a folder of reference docs to a live meeting.

Two jobs:
  1. Retrieval — surface the passages most relevant to what was just said,
     so the LLM can suggest good questions to ask (lightweight keyword TF
     overlap; no embedding models, keeps the live path fast and offline).
  2. Whisper priming — derive an initial_prompt + hotwords from the docs so
     domain vocab / names transcribe correctly.
"""

from __future__ import annotations

import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

_TEXT_EXTENSIONS = {".txt", ".md", ".markdown", ".rst", ".text", ".org", ".csv"}
_MAX_FILE_BYTES = 2_000_000
_CHUNK_WORDS = 180

# Reuse a small English stop list for keyword overlap.
_STOP_WORDS = frozenset("""
a an the is are was were be been being have has had do does did will would
shall should may might can could of in to for on with at by from about into
through during before after above below between out off over under again then
once here there when where why how all each every both few more most other some
such no nor not only own same so than too very and but or if what which who whom
this that these those i me my we our you your he she it they them their as at
""".split())


@dataclass
class Chunk:
    source: str
    text: str
    keywords: Counter


@dataclass
class Context:
    chunks: list[Chunk]
    initial_prompt: str
    hotwords: str

    @property
    def is_empty(self) -> bool:
        return not self.chunks


def _tokenize(text: str) -> list[str]:
    return re.findall(r"[a-zA-Z][a-zA-Z0-9'-]+", text.lower())


def _keywords(text: str) -> Counter:
    return Counter(w for w in _tokenize(text) if w not in _STOP_WORDS and len(w) > 2)


def _chunk_text(text: str) -> list[str]:
    """Split into ~_CHUNK_WORDS windows on paragraph boundaries."""
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    buf: list[str] = []
    count = 0
    for para in paras:
        n = len(para.split())
        if buf and count + n > _CHUNK_WORDS:
            chunks.append("\n\n".join(buf))
            buf, count = [], 0
        buf.append(para)
        count += n
    if buf:
        chunks.append("\n\n".join(buf))
    return chunks


def _proper_nouns(text: str) -> list[str]:
    """Capitalized words/spans likely to be names or domain terms."""
    spans = re.findall(r"\b([A-Z][a-zA-Z0-9]+(?:\s+[A-Z][a-zA-Z0-9]+){0,2})\b", text)
    seen: dict[str, None] = {}
    for s in spans:
        if s.lower() in _STOP_WORDS:
            continue
        seen.setdefault(s, None)
    return list(seen)


def load_context(folder: str | Path) -> Context:
    """Read a folder of text docs into a retrievable, priming-ready Context."""
    root = Path(folder).expanduser()
    if not root.is_dir():
        return Context(chunks=[], initial_prompt="", hotwords="")

    chunks: list[Chunk] = []
    proper: Counter = Counter()
    term_freq: Counter = Counter()

    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in _TEXT_EXTENSIONS:
            continue
        try:
            if path.stat().st_size > _MAX_FILE_BYTES:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        rel = str(path.relative_to(root))
        for piece in _chunk_text(text):
            chunks.append(Chunk(source=rel, text=piece, keywords=_keywords(piece)))
        for name in _proper_nouns(text):
            proper[name] += 1
        term_freq.update(_keywords(text))

    # Whisper priming: proper nouns as hotwords; a short vocab line as prompt.
    hot = [name for name, _ in proper.most_common(40)]
    top_terms = [t for t, _ in term_freq.most_common(30)]
    initial_prompt = ""
    if hot or top_terms:
        vocab = ", ".join(dict.fromkeys(hot + top_terms))
        initial_prompt = f"Meeting about: {vocab}."
    hotwords = ", ".join(hot[:20])

    return Context(chunks=chunks, initial_prompt=initial_prompt, hotwords=hotwords)


def retrieve(context: Context, query: str, k: int = 4) -> list[Chunk]:
    """Top-k chunks by keyword overlap with the query text."""
    if context.is_empty:
        return []
    q = _keywords(query)
    if not q:
        return []

    def score(chunk: Chunk) -> float:
        # Sum of query-term frequencies present in the chunk.
        return float(sum(chunk.keywords.get(term, 0) * cnt for term, cnt in q.items()))

    ranked = sorted(context.chunks, key=score, reverse=True)
    return [c for c in ranked if score(c) > 0][:k]
