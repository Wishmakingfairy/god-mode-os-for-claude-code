#!/usr/bin/env python3
"""god-mode-os router query.

Two paths based on prompt length:
  Short (<= 20 words): single embedding, cosine top-K with threshold.
  Long (> 20 words):  multi-query fan-out (sentence + Ollama keyword extraction)
                      + BM25 hybrid via Postgres FTS, fused scoring.

Configuration (env vars, same as indexer.py):
  GMOS_DB_DSN, GMOS_OLLAMA_URL, GMOS_EMBED_MODEL, GMOS_OLLAMA_MODEL

Outputs JSON when --json passed (used by context-router.sh hook).
"""
import argparse
import json
import os
import re
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

OLLAMA_URL = os.environ.get("GMOS_OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.environ.get("GMOS_EMBED_MODEL", "nomic-embed-text")
CHAT_MODEL = os.environ.get("GMOS_OLLAMA_MODEL", "llama3.2")
OLLAMA_BIN = os.environ.get("GMOS_OLLAMA", "/opt/homebrew/bin/ollama")
PG_DSN = os.environ.get("GMOS_DB_DSN", "dbname=gmos_router")
LONG_PROMPT_WORDS = 20

# Fused score weights (cosine dominant, BM25 tiebreaker)
W_COSINE = 0.8
W_BM25 = 0.2


def _clean(t):
    return (t or "empty").replace("\x00", "")


def embed(text):
    text = _clean(text)
    payload = json.dumps({"model": EMBED_MODEL, "prompt": text[:8000]}).encode()
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/embeddings",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=10).read())["embedding"]


def vec_literal(vec):
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


def split_sentences(text):
    text = _clean(text)
    parts = re.split(r"(?<=[.!?])\s+(?=[A-Z0-9])|[\n]{2,}", text)
    return [s.strip() for s in parts if s and len(s.strip()) > 8]


def extract_keywords(long_text, n=5):
    text = _clean(long_text).strip()
    if not text or not os.path.exists(OLLAMA_BIN):
        return []
    try:
        prompt = (
            f"Extract the top {n} specific technologies, product names, "
            "or technical concepts from the user message below. "
            "Reply with a single comma-separated line. No preamble.\n\n"
            f"User message:\n{text[:3000]}\n\nKeywords:"
        )
        r = subprocess.run(
            [OLLAMA_BIN, "run", CHAT_MODEL, prompt],
            capture_output=True, text=True, timeout=8,
        )
        line = (r.stdout or "").strip().split("\n")[0]
        if line.lower().startswith("keywords:"):
            line = line.split(":", 1)[1]
        parts = [p.strip().lower() for p in line.split(",")]
        return [p for p in parts if p and 2 <= len(p) <= 40][:n]
    except Exception:
        return []


def query_skills_cosine(cur, vec_lit, top=10):
    cur.execute(
        "SELECT name, description, 1 - (embedding <=> %s::vector) AS sim "
        "FROM skills ORDER BY embedding <=> %s::vector LIMIT %s",
        (vec_lit, vec_lit, top),
    )
    return [
        {"name": r[0], "description": r[1] or "", "cosine": float(r[2])}
        for r in cur.fetchall()
    ]


def query_files_cosine(cur, vec_lit, top=5):
    cur.execute(
        "SELECT path, chunk_index, LEFT(content, 300), "
        "1 - (embedding <=> %s::vector) AS sim "
        "FROM files ORDER BY embedding <=> %s::vector LIMIT %s",
        (vec_lit, vec_lit, top),
    )
    return [
        {"ref": r[0], "chunk": r[1], "snippet": r[2], "cosine": float(r[3])}
        for r in cur.fetchall()
    ]


def _build_or_tsquery(text):
    toks = re.findall(r"[A-Za-z][A-Za-z0-9]{2,}", _clean(text).lower())
    stop = {"the", "and", "for", "with", "use", "when", "that", "this", "from",
            "into", "your", "what", "which", "should", "need", "want", "like",
            "will", "have", "can", "its", "their", "any", "has", "are", "was",
            "does", "set", "setup", "using", "new", "how", "why", "where", "make"}
    toks = [t for t in toks if t not in stop]
    seen, uniq = set(), []
    for t in toks:
        if t not in seen:
            seen.add(t)
            uniq.append(t)
    return " | ".join(uniq[:25]) if uniq else None


def query_skills_bm25(cur, text, top=10):
    tsq = _build_or_tsquery(text)
    if not tsq:
        return []
    try:
        cur.execute(
            "SELECT name, description, "
            "ts_rank(to_tsvector('english', description), to_tsquery('english', %s)) AS rank "
            "FROM skills "
            "WHERE to_tsvector('english', description) @@ to_tsquery('english', %s) "
            "ORDER BY rank DESC LIMIT %s",
            (tsq, tsq, top),
        )
    except Exception:
        return []
    return [
        {"name": r[0], "description": r[1] or "", "bm25": float(r[2])}
        for r in cur.fetchall()
    ]


def fuse_scores(cosine_hits, bm25_hits, key="name"):
    by_key = {h[key]: dict(h) for h in cosine_hits}
    bm_vals = [h["bm25"] for h in bm25_hits]
    bm_max = max(bm_vals) if bm_vals else 1.0
    if bm_max <= 0:
        bm_max = 1.0
    for h in bm25_hits:
        k = h[key]
        bm_norm = h["bm25"] / bm_max
        if k in by_key:
            by_key[k]["bm25_norm"] = max(by_key[k].get("bm25_norm", 0), bm_norm)
        else:
            nh = dict(h)
            nh["cosine"] = 0.0
            nh["bm25_norm"] = bm_norm
            by_key[k] = nh
    out = []
    for v in by_key.values():
        v.setdefault("bm25_norm", 0.0)
        v.setdefault("cosine", 0.0)
        v["fused"] = W_COSINE * v["cosine"] + W_BM25 * v["bm25_norm"]
        out.append(v)
    out.sort(key=lambda x: x["fused"], reverse=True)
    return out


def _embed_safe(q):
    try:
        return q, embed(q)
    except Exception:
        return q, None


def long_prompt_skills(cur, prompt_text, top=5):
    sentences = split_sentences(prompt_text)[:6]
    keywords = extract_keywords(prompt_text, n=5)
    queries = [prompt_text] + sentences + keywords
    seen, uniq = set(), []
    for q in queries:
        qn = (q or "").strip().lower()
        if qn and qn not in seen:
            seen.add(qn)
            uniq.append(q)
    uniq = uniq[:12]
    embeddings = {}
    with ThreadPoolExecutor(max_workers=6) as ex:
        for fut in as_completed([ex.submit(_embed_safe, q) for q in uniq]):
            q, vec = fut.result()
            if vec is not None:
                embeddings[q] = vec
    candidate_map = {}
    for q, vec in embeddings.items():
        try:
            for h in query_skills_cosine(cur, vec_literal(vec), top=10):
                k = h["name"]
                if k not in candidate_map or h["cosine"] > candidate_map[k]["cosine"]:
                    candidate_map[k] = dict(h)
        except Exception:
            continue
    bm25_hits = query_skills_bm25(cur, prompt_text, top=20)
    fused = fuse_scores(list(candidate_map.values()), bm25_hits)
    return fused[:top]


def short_prompt_skills(cur, prompt_text, top=5, threshold=0.55):
    vec = embed(prompt_text)
    hits = query_skills_cosine(cur, vec_literal(vec), top=top * 2)
    return [h for h in hits if h["cosine"] >= threshold][:top]


def files_path(cur, prompt_text, top=2, threshold=0.5, hybrid=True):
    vec = embed(prompt_text)
    cos = query_files_cosine(cur, vec_literal(vec), top=10)
    if hybrid:
        return [f for f in cos if f["cosine"] >= threshold][:top]
    return [f for f in cos if f["cosine"] >= threshold][:top]


def merged_query(args):
    import psycopg2
    conn = psycopg2.connect(PG_DSN)
    cur = conn.cursor()
    prompt = _clean(args.q)
    word_count = len(prompt.split())
    is_long = word_count > LONG_PROMPT_WORDS

    if is_long:
        skills = long_prompt_skills(cur, prompt, top=args.skills_top)
        skills = [s for s in skills if s.get("fused", s.get("cosine", 0)) >= args.long_threshold]
        path = "fan-out+bm25"
    else:
        skills = short_prompt_skills(cur, prompt, top=args.skills_top, threshold=args.skills_threshold)
        path = "single-embed"

    files = files_path(cur, prompt, top=args.files_top, threshold=args.files_threshold, hybrid=is_long)
    conn.close()
    return {
        "query": prompt[:200],
        "word_count": word_count,
        "path": path,
        "skills": [
            {
                "name": s["name"],
                "description": s.get("description", ""),
                "sim": round(float(s.get("fused", s.get("cosine", 0))), 3),
            }
            for s in skills
        ],
        "files": [
            {
                "ref": f.get("ref"),
                "snippet": f.get("snippet", ""),
                "sim": round(float(f.get("cosine", 0)), 3),
            }
            for f in files
        ],
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("q", help="query text")
    p.add_argument("--merged", action="store_true")
    p.add_argument("--skills-top", type=int, default=5)
    p.add_argument("--files-top", type=int, default=2)
    p.add_argument("--skills-threshold", type=float, default=0.55)
    p.add_argument("--files-threshold", type=float, default=0.5)
    p.add_argument("--long-threshold", type=float, default=0.35)
    p.add_argument("--json", action="store_true")
    args = p.parse_args()

    try:
        out = merged_query(args)
        if args.json:
            print(json.dumps(out))
        else:
            print(f"[{out['path']}] Query ({out['word_count']} words): {out['query']!r}")
            print(f"Skills top-{len(out['skills'])}:")
            for s in out["skills"]:
                print(f"  [{s['sim']:.3f}] {s['name']}: {s['description'][:100]}")
            print(f"Files top-{len(out['files'])}:")
            for f in out["files"]:
                print(f"  [{f['sim']:.3f}] {os.path.basename(f['ref'] or '')}: {f['snippet'][:80]}")
    except Exception as e:
        if args.json:
            print(json.dumps({"error": str(e), "skills": [], "files": []}))
        else:
            print(f"ERROR: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
