#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f .env ]; then
  echo "copy .env.example to .env and set replace_me secrets first" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
. ./.env
set +a

if grep -E '^[A-Za-z_][A-Za-z0-9_]*=.*replace_me' .env >/dev/null; then
  echo "replace every replace_me value in .env before starting" >&2
  exit 1
fi

EDGE_NETWORK=${EDGE_NETWORK:-proxy}
if ! docker network inspect "$EDGE_NETWORK" >/dev/null 2>&1; then
  echo "creating edge network $EDGE_NETWORK (exists on the Console host as proxy)"
  docker network create "$EDGE_NETWORK" >/dev/null
fi

exec docker compose up -d "$@"
