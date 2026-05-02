#!/usr/bin/env python3
"""god-mode-os router indexer.

Walks configured paths, embeds via Ollama (nomic-embed-text), upserts to Postgres.

Configuration (env vars):
  GMOS_DB_DSN              Postgres DSN. Default: dbname=gmos_router
  GMOS_OLLAMA_URL          Ollama HTTP base. Default: http://localhost:11434
  GMOS_EMBED_MODEL         Embedding model. Default: nomic-embed-text
  GMOS_FILE_SCOPE          Colon-separated paths to index for files. Default: none.
  GMOS_SKILL_SCOPE         Path to .claude/skills/ directory. Default: ~/.claude/skills
  GMOS_LOG                 Log file path. Default: ~/.god-mode-os/indexer.log
  GMOS_EXCLUDE_FILENAMES   Comma-separated filenames to exclude. Default:
                           correction-log.md,correction-log-pending.md

Chunking: files under 2000 chars get 1 embedding; larger files split into 2000-char chunks.
Incremental: stores SHA-256 content hash, skips unchanged files.
"""
import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.request

OLLAMA_URL = os.environ.get("GMOS_OLLAMA_URL", "http://localhost:11434")
EMBED_MODEL = os.environ.get("GMOS_EMBED_MODEL", "nomic-embed-text")
PG_DSN = os.environ.get("GMOS_DB_DSN", "dbname=gmos_router")
HOME = pathlib.Path.home()
LOG = pathlib.Path(os.environ.get("GMOS_LOG", str(HOME / ".god-mode-os" / "indexer.log")))

FILE_SCOPE = [
    pathlib.Path(p).expanduser()
    for p in os.environ.get("GMOS_FILE_SCOPE", "").split(":")
    if p
]
SKILL_SCOPE = pathlib.Path(
    os.environ.get("GMOS_SKILL_SCOPE", str(HOME / ".claude" / "skills"))
).expanduser()

EXCLUDE_FILENAMES = set(
    s.strip()
    for s in os.environ.get(
        "GMOS_EXCLUDE_FILENAMES", "correction-log.md,correction-log-pending.md"
    ).split(",")
    if s.strip()
)

CHUNK_THRESHOLD = 2000
CHUNK_SIZE = 2000


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line, flush=True)
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a") as f:
            f.write(line + "\n")
    except Exception:
        pass


def ollama_healthcheck():
    try:
        urllib.request.urlopen(f"{OLLAMA_URL}/api/tags", timeout=3).read()
        return True
    except Exception as e:
        log(f"Ollama down: {e}")
        return False


def embed(text):
    payload = json.dumps({"model": EMBED_MODEL, "prompt": text[:8000]}).encode()
    req = urllib.request.Request(
        f"{OLLAMA_URL}/api/embeddings",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    return json.loads(urllib.request.urlopen(req, timeout=30).read())["embedding"]


def sha(text):
    return hashlib.sha256(text.encode("utf-8", "ignore")).hexdigest()[:16]


def chunk_text(text):
    if len(text) <= CHUNK_THRESHOLD:
        return [(0, text)]
    return [
        (i // CHUNK_SIZE, text[i : i + CHUNK_SIZE])
        for i in range(0, len(text), CHUNK_SIZE)
    ]


def vec_literal(vec):
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


def get_conn():
    try:
        import psycopg2
    except ImportError:
        log("psycopg2 missing. Install: pip3 install psycopg2-binary")
        sys.exit(1)
    return psycopg2.connect(PG_DSN)


def index_files(conn):
    if not FILE_SCOPE:
        log("No file scope configured (set GMOS_FILE_SCOPE), skipping files.")
        return
    cur = conn.cursor()
    indexed, skipped, errored = 0, 0, 0
    for root in FILE_SCOPE:
        if not root.exists():
            continue
        for path in root.rglob("*.md"):
            if path.name in EXCLUDE_FILENAMES:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
                if not text.strip():
                    continue
                file_hash = sha(text)
                cur.execute(
                    "SELECT content_hash FROM files WHERE path=%s AND chunk_index=0",
                    (str(path),),
                )
                row = cur.fetchone()
                if row and row[0] == file_hash:
                    skipped += 1
                    continue
                cur.execute("DELETE FROM files WHERE path=%s", (str(path),))
                for idx, chunk in chunk_text(text):
                    vec = embed(chunk)
                    cur.execute(
                        "INSERT INTO files (path, chunk_index, content_hash, content, embedding) "
                        "VALUES (%s, %s, %s, %s, %s::vector)",
                        (str(path), idx, file_hash, chunk, vec_literal(vec)),
                    )
                indexed += 1
                if indexed % 20 == 0:
                    conn.commit()
                    log(f"files: indexed={indexed} skipped={skipped}")
            except Exception as e:
                errored += 1
                log(f"FILE ERROR {path}: {e}")
    conn.commit()
    log(f"files done: indexed={indexed} skipped={skipped} errored={errored}")


def index_skills(conn):
    if not SKILL_SCOPE.exists():
        log(f"Skill scope missing: {SKILL_SCOPE}, skipping.")
        return
    cur = conn.cursor()
    indexed, skipped, errored = 0, 0, 0
    for skill_dir in SKILL_SCOPE.iterdir():
        if not skill_dir.is_dir():
            continue
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            continue
        try:
            text = skill_md.read_text(encoding="utf-8", errors="ignore")
            if not text.strip():
                continue
            body = text[:2000]
            file_hash = sha(text)
            name = skill_dir.name
            desc = ""
            if text.startswith("---"):
                parts = text.split("---", 2)
                if len(parts) >= 2:
                    for line in parts[1].splitlines():
                        if line.strip().startswith("description:"):
                            desc = line.split(":", 1)[1].strip()
                            break
            if not desc:
                desc = body[:300]
            cur.execute("SELECT content_hash FROM skills WHERE name=%s", (name,))
            row = cur.fetchone()
            if row and row[0] == file_hash:
                skipped += 1
                continue
            vec = embed(f"{name}: {desc}\n\n{body}")
            cur.execute(
                "INSERT INTO skills (name, path, description, content_hash, embedding) "
                "VALUES (%s, %s, %s, %s, %s::vector) "
                "ON CONFLICT (name) DO UPDATE SET "
                "path=EXCLUDED.path, description=EXCLUDED.description, "
                "content_hash=EXCLUDED.content_hash, embedding=EXCLUDED.embedding, "
                "updated_at=NOW()",
                (name, str(skill_md), desc, file_hash, vec_literal(vec)),
            )
            indexed += 1
            if indexed % 25 == 0:
                conn.commit()
                log(f"skills: indexed={indexed} skipped={skipped}")
        except Exception as e:
            errored += 1
            log(f"SKILL ERROR {skill_dir.name}: {e}")
    conn.commit()
    log(f"skills done: indexed={indexed} skipped={skipped} errored={errored}")


def main():
    log("indexer start")
    if not ollama_healthcheck():
        log("ABORT: Ollama not reachable")
        sys.exit(0)
    try:
        conn = get_conn()
    except Exception as e:
        log(f"ABORT: cannot connect to Postgres: {e}")
        sys.exit(0)
    try:
        index_files(conn)
        index_skills(conn)
    finally:
        conn.close()
    log("indexer done")


if __name__ == "__main__":
    main()
