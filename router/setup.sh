#!/bin/bash
# god-mode-os router setup
# Brings up Postgres+pgvector via Docker, pulls Ollama models, creates DB schema,
# runs initial index of skills (~/.claude/skills) and any configured doc folders.
#
# Idempotent: re-run anytime to re-apply schema and re-index.

set -eu

GMOS_HOME="${GMOS_HOME:-$HOME/.god-mode-os}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$GMOS_HOME"

# Default DSN points at the docker-compose container on port 5433.
export GMOS_DB_DSN="${GMOS_DB_DSN:-host=localhost port=5433 dbname=gmos_router user=gmos password=gmos}"

echo "==> Checking dependencies"
command -v docker >/dev/null 2>&1 || { echo "ERROR: docker required (install Docker Desktop)"; exit 1; }
command -v ollama >/dev/null 2>&1 || { echo "ERROR: ollama required (brew install ollama)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required"; exit 1; }
python3 -c "import psycopg2" 2>/dev/null || { echo "Installing psycopg2..."; pip3 install --user psycopg2-binary; }

echo "==> Starting Postgres+pgvector container"
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

echo "==> Waiting for Postgres health"
for i in $(seq 1 30); do
    if docker exec gmos-postgres pg_isready -U gmos -d gmos_router >/dev/null 2>&1; then
        echo "    Postgres ready"
        break
    fi
    sleep 1
done

echo "==> Applying schema"
docker exec -i gmos-postgres psql -U gmos -d gmos_router < "$SCRIPT_DIR/sql/schema.sql"

echo "==> Pulling Ollama models (nomic-embed-text, llama3.2)"
ollama pull nomic-embed-text
ollama pull llama3.2

echo "==> Linking router/query.py for hook discoverability"
ln -sf "$SCRIPT_DIR/vector/query.py" "$GMOS_HOME/router/query.py" 2>/dev/null || {
    mkdir -p "$GMOS_HOME/router"
    ln -sf "$SCRIPT_DIR/vector/query.py" "$GMOS_HOME/router/query.py"
}

echo "==> Initial indexing (skills only by default; set GMOS_FILE_SCOPE for personal docs)"
python3 "$SCRIPT_DIR/vector/indexer.py"

echo ""
echo "Router ready."
echo "Test:  python3 $SCRIPT_DIR/vector/query.py 'how do I optimize a postgres query' --merged"
echo "Hook:  set GMOS_ROUTER_QUERY=$SCRIPT_DIR/vector/query.py and add hooks/routing/context-router.sh as UserPromptSubmit"
