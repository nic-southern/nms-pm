#!/bin/sh
# Create or update the Plane OIDC client on the live nms realm. Run on the droplet.
# Reads only the keys it needs and does not print secrets.
set -eu

IDP_ENV=${IDP_ENV:-/opt/nms-idp/.env}
PM_ENV=${PM_ENV:-/opt/nms-pm/.env}

if [ ! -f "$IDP_ENV" ]; then
  echo "missing $IDP_ENV" >&2
  exit 1
fi
if [ ! -f "$PM_ENV" ]; then
  echo "missing $PM_ENV" >&2
  exit 1
fi

env_get() {
  python3 - "$1" "$2" <<'PY'
import sys
path, key = sys.argv[1], sys.argv[2]
for raw in open(path, encoding="utf-8"):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith(key + "="):
        sys.stdout.write(line.split("=", 1)[1])
        break
PY
}

PUBLIC_URL=$(env_get "$PM_ENV" PUBLIC_URL)
PUBLIC_URL=${PUBLIC_URL:-https://pm.newmarketsecurity.com}
CLIENT_ID=$(env_get "$PM_ENV" OIDC_CLIENT_ID)
CLIENT_ID=${CLIENT_ID:-plane}
OIDC_CLIENT_SECRET=$(env_get "$PM_ENV" OIDC_CLIENT_SECRET)
KC_BOOTSTRAP_ADMIN_USERNAME=$(env_get "$IDP_ENV" KC_BOOTSTRAP_ADMIN_USERNAME)
KC_BOOTSTRAP_ADMIN_PASSWORD=$(env_get "$IDP_ENV" KC_BOOTSTRAP_ADMIN_PASSWORD)
KC_CONTAINER=${KC_CONTAINER:-nms-idp-keycloak-1}

if [ -z "${OIDC_CLIENT_SECRET:-}" ] || [ "$OIDC_CLIENT_SECRET" = "replace_me" ]; then
  echo "OIDC_CLIENT_SECRET is not set in the project-management host env" >&2
  exit 1
fi

kcadm() {
  docker exec "$KC_CONTAINER" /opt/keycloak/bin/kcadm.sh "$@"
}

kcadm config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KC_BOOTSTRAP_ADMIN_USERNAME" \
  --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" >/dev/null

CLIENT_UUID=$(kcadm get clients -r nms -q "clientId=$CLIENT_ID" --fields id,clientId \
  | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)

if [ -z "$CLIENT_UUID" ]; then
  kcadm create clients -r nms \
    -s "clientId=$CLIENT_ID" \
    -s "name=Project management" \
    -s "enabled=true" \
    -s "protocol=openid-connect" \
    -s "publicClient=false" \
    -s "clientAuthenticatorType=client-secret" \
    -s "standardFlowEnabled=true" \
    -s "implicitFlowEnabled=false" \
    -s "directAccessGrantsEnabled=false" \
    -s "frontchannelLogout=true" \
    >/dev/null
  CLIENT_UUID=$(kcadm get clients -r nms -q "clientId=$CLIENT_ID" --fields id,clientId \
    | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
fi

if [ -z "$CLIENT_UUID" ]; then
  echo "could not create or find OIDC client $CLIENT_ID in realm nms" >&2
  exit 1
fi

kcadm update "clients/$CLIENT_UUID" -r nms \
  -s "secret=$OIDC_CLIENT_SECRET" \
  -s "rootUrl=$PUBLIC_URL" \
  -s "baseUrl=$PUBLIC_URL" \
  -s 'redirectUris=["'"$PUBLIC_URL"'/oauth2/callback","'"$PUBLIC_URL"'/auth/oidc/callback/"]' \
  -s 'webOrigins=["'"$PUBLIC_URL"'"]' \
  -s 'attributes."pkce.code.challenge.method"=S256' \
  -s 'attributes."post.logout.redirect.uris"="'"$PUBLIC_URL"'/*"' \
  >/dev/null

echo "updated realm nms client $CLIENT_ID redirect URIs for $PUBLIC_URL"
