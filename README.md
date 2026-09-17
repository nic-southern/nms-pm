# nms-pm

Company project management for New Market Security. Official [Windshift](https://windshift.sh/), Compose, and sign-in against realm `nms` at https://auth.newmarketsecurity.com.

Public hostname: https://pm.newmarketsecurity.com

The GitHub repository stays `nms-pm` so existing `pm` host paths and docs keep working. This is not part of the Lockhaven application repo and does not share a database with Lockhaven, Keycloak, or tickets. It is not a custom project-management app: the repo is glue only.

## What ships

- Official Windshift image (`ghcr.io/windshiftapp/windshift`, pinned in `.env`)
- Native OpenID Connect to Keycloak realm `nms` (PKCE). Configure and inspect it later under Admin > Single Sign-On
- Docker Compose project `nms-pm` on the existing `proxy` network
- Keycloak client `pm` (created/updated by `scripts/ensure-oidc-client.sh`)

There is no oauth2-proxy and no second Caddy. Secrets stay in `.env`. Do not commit `.env` or real project contents.

## Boot locally

Requires Docker Compose and a `.env` with real random values (not `replace_me`). Keycloak must already be reachable for sign-in.

```sh
cp .env.example .env
./scripts/up.sh
```

`scripts/up.sh` creates the edge network (`proxy` by default) if it is missing. Compose publishes Windshift only on loopback `http://localhost:8088`. Postgres is not published to the host network.

## DNS and TLS

Do not start a second Caddy from this repo, and do not publish 80/443 here. The Console host already terminates TLS. This stack joins that edge network and lets the existing watcher pick up labels.

1. DNS for `pm.newmarketsecurity.com` already points at the Console VPS.
2. Copy `.env.example` to `.env` on the host. Set `PUBLIC_HOST=pm.newmarketsecurity.com`, `PUBLIC_URL=https://pm.newmarketsecurity.com`, `OIDC_ISSUER=https://auth.newmarketsecurity.com/realms/nms`, `OIDC_CLIENT_ID=pm`, `OIDC_SLUG=nms`, `EDGE_NETWORK=proxy`. Generate `SSO_SECRET` with `openssl rand -hex 32` and keep it stable.
3. Host layout: `/opt/nms-pm` (not `/opt/lockhaven`).
4. Register the live client: `./scripts/ensure-oidc-client.sh`
5. Start this project only: `docker compose up -d`
6. Finish first-run admin + seed SSO: `./scripts/bootstrap.sh`

HTTP stays bound to `127.0.0.1:8088`. Labels cover caddy-docker-proxy and Traefik on the `proxy` network. `USE_PROXY=true` so Windshift trusts forwarded proto/IP from that edge only.

Keep project name `nms-pm`. Do not run a second Lockhaven worker from this repo. Do not start CRM or Zammad from this repo. Tickets stay in `nms-desk`.

## Sign-in

Windshift talks to Keycloak itself. Public HTTPS hits Windshift, the login page offers **Sign in with SSO**, then realm `nms` client `pm` with PKCE.

Issuer (OIDC discovery):

```text
https://auth.newmarketsecurity.com/realms/nms
```

Redirect URI on the client:

```text
https://pm.newmarketsecurity.com/api/sso/callback/nms
```

Login start path: `/api/sso/login/nms`. Provider slug `nms` is what Admin > Single Sign-On shows.

The first boot still creates one local instance admin (`POST /api/setup/complete`) so recovery works. After you sign in once with Keycloak, set Admin > Authentication to SSO required if you want the password form hidden. Keep `ENABLE_ADMIN_FALLBACK=true` in the host env for emergency password access.

## Replacing Plane

This repo previously fronted Plane Community with oauth2-proxy, which prompted Keycloak and then Plane's own login. Tear that stack down before starting Windshift:

```sh
cd /opt/nms-pm
docker compose down -v
```

That removes Plane volumes. Project data from the Plane trial is not migrated.

## Safety

Never commit passwords, SSO secrets, OIDC client secrets, or project contents. Postgres is not published. This stack must not bind host 80/443.
