#!/bin/sh
# Encrypt the Keycloak client secret into Windshift sso_providers. Run on the droplet
# after Windshift is healthy. Does not print secrets.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [ ! -f .env ]; then
  echo "missing .env" >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
. ./.env
set +a

NETWORK=${COMPOSE_NETWORK:-nms-pm}
if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
  echo "docker network $NETWORK is missing; start compose first" >&2
  exit 1
fi

exec docker run --rm --network "$NETWORK" \
  -e SSO_SECRET \
  -e OIDC_CLIENT_SECRET \
  -e OIDC_ISSUER \
  -e OIDC_CLIENT_ID \
  -e OIDC_SLUG \
  -e OIDC_SCOPES \
  -e OIDC_PROVIDER_NAME \
  -e POSTGRES_HOST=postgres \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_USER \
  -e POSTGRES_PASSWORD \
  -e POSTGRES_DB \
  -v "$ROOT/scripts/seed-oidc.py:/seed.py:ro" \
  python:3.12-slim \
  bash -c "pip install -q cryptography 'psycopg[binary]' && python /seed.py"
