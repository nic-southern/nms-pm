#!/bin/sh
# First-run Windshift admin plus Keycloak SSO seed. Run on the droplet after up.sh.
# Does not print secrets.
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

LISTEN_HTTP_PORT=${LISTEN_HTTP_PORT:-8088}
BASE="http://127.0.0.1:${LISTEN_HTTP_PORT}"

wait_ready() {
  i=0
  while [ "$i" -lt 60 ]; do
    if curl -fsS "$BASE/readyz" >/dev/null 2>&1; then
      return 0
    fi
    i=$((i + 1))
    sleep 2
  done
  echo "windshift was not ready on $BASE/readyz" >&2
  return 1
}

wait_ready

python3 - "$BASE" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base = sys.argv[1]
status = json.load(urllib.request.urlopen(f"{base}/api/setup/status", timeout=15))
if status.get("setup_completed"):
    print("setup already completed")
    raise SystemExit(0)

email = os.environ.get("SETUP_ADMIN_EMAIL", "").strip()
username = os.environ.get("SETUP_ADMIN_USERNAME", "admin").strip()
password = os.environ.get("SETUP_ADMIN_PASSWORD", "").strip()
first_name = os.environ.get("SETUP_ADMIN_FIRST_NAME", "Admin").strip()
last_name = os.environ.get("SETUP_ADMIN_LAST_NAME", "User").strip()
if not email or email == "replace_me" or not password or password == "replace_me":
    print("SETUP_ADMIN_EMAIL/PASSWORD not set; skip first-run setup", file=sys.stderr)
    raise SystemExit(1)

body = json.dumps(
    {
        "admin_user": {
            "email": email,
            "username": username,
            "password": password,
            "first_name": first_name,
            "last_name": last_name,
        },
        "module_settings": {
            "time_tracking_enabled": True,
            "test_management_enabled": False,
        },
    }
).encode("utf-8")
req = urllib.request.Request(
    f"{base}/api/setup/complete",
    data=body,
    method="POST",
    headers={"Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
except urllib.error.HTTPError as exc:
    detail = exc.read().decode("utf-8", "replace")
    print(f"setup failed HTTP {exc.code}", file=sys.stderr)
    print(detail, file=sys.stderr)
    raise SystemExit(1)
if not payload.get("success"):
    print("setup did not report success", file=sys.stderr)
    raise SystemExit(1)
print("initial setup completed")
PY

"$ROOT/scripts/seed-oidc.sh"

echo "bootstrap finished; confirm /api/sso/status and Sign in with SSO"
