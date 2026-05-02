-- god-mode-os router schema
-- Run: psql gmos_router -f schema.sql
-- Requires: pgvector extension

CREATE EXTENSION IF NOT EXISTS vector;

-- Files: markdown indexed from configured source paths.
CREATE TABLE IF NOT EXISTS files (
  id            BIGSERIAL PRIMARY KEY,
  path          TEXT NOT NULL,
  chunk_index   INTEGER NOT NULL DEFAULT 0,
  content_hash  TEXT NOT NULL,
  content       TEXT NOT NULL,
  embedding     vector(768) NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (path, chunk_index)
);

CREATE INDEX IF NOT EXISTS files_path_idx ON files (path);
CREATE INDEX IF NOT EXISTS files_content_fts_idx ON files USING gin (to_tsvector('english', content));

-- Skills: one embedding per SKILL.md (description + first 2000 chars of body).
CREATE TABLE IF NOT EXISTS skills (
  id            BIGSERIAL PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE,
  path          TEXT NOT NULL,
  description   TEXT NOT NULL,
  content_hash  TEXT NOT NULL,
  embedding     vector(768) NOT NULL,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS skills_desc_fts_idx ON skills USING gin (to_tsvector('english', description));

-- NO IVFFlat indexes by default.
-- Stress test (679 prompts) showed IVFFlat with lists=50 + default probes=1
-- returns near-random results (28% top-1 vs 81% on sequential scan).
-- Under ~10k rows, sequential scan is faster AND 100% recall.
-- Add HNSW or higher probes only if row counts cross 10k.
