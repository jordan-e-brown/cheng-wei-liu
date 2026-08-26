#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/Backend"

if [[ ! -x .venv/bin/uvicorn ]]; then
  python3 -m venv .venv
  .venv/bin/pip install -r requirements.txt
fi

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is not set. Copy Backend/.env.example to Backend/.env and edit it." >&2
  exit 1
fi

echo "Starting 汉语谈话 backend on all LAN interfaces: http://0.0.0.0:8000"
exec .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
