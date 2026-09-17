# nms-pm

Company project management for New Market Security. Official Plane, Compose, and sign-in against realm nms at https://auth.newmarketsecurity.com.

Public hostname: pm.newmarketsecurity.com

This is not part of the Lockhaven application repo and does not share a database with Lockhaven, Keycloak, or tickets. It is not a custom project-management app: the repo is glue only.

## What ships

- Official Plane Community images (`makeplane/plane-*`, pinned release in `.env`)
- oauth2-proxy in front of Plane so operators sign in with the same Keycloak realm as Console and tickets
- Docker Compose project `nms-pm` on the existing `proxy` network
- Keycloak client `plane` (created/updated by `scripts/ensure-plane-client.sh`)

Secrets stay in `.env`. Do not commit `.env` or real project contents.

## Boot locally

Requires Docker Compose and a `.env` with real random values (not `replace_me`). Keycloak must already be reachable for sign-in.

```sh
cp .env.example .env
./scripts/up.sh
```

`scripts/up.sh` creates the edge network (`proxy` by default) if it is missing. Compose publishes only on loopback:

- Plane (behind SSO): http://localhost:4180
- Plane router without SSO: http://localhost:8088

Postgres, Redis, RabbitMQ, and MinIO are not published to the host network.

## DNS and TLS

Do not start a second Caddy from this repo, and do not publish 80/443 here. The Console host already terminates TLS. This stack joins that edge network and lets the existing watcher pick up labels.

1. DNS for `pm.newmarketsecurity.com` already points at the Console VPS.
2. Copy `.env.example` to `.env` on the host. Set `PUBLIC_HOST=pm.newmarketsecurity.com`, `PUBLIC_URL=https://pm.newmarketsecurity.com`, `WEB_URL` and `CORS_ALLOWED_ORIGINS` to that origin, `OIDC_ISSUER=https://auth.newmarketsecurity.com/realms/nms`, `OIDC_CLIENT_ID=plane`, `EDGE_NETWORK=proxy`.
3. Host layout: `/opt/nms-pm` (not `/opt/lockhaven`).
4. Register the live client: `./scripts/ensure-plane-client.sh`
5. Start this project only: `docker compose up -d`

HTTP stays bound to `127.0.0.1:8088` (Plane router) and `127.0.0.1:4180` (SSO). Labels cover caddy-docker-proxy and Traefik on the `proxy` network.

Keep project name `nms-pm`. Do not run a second Lockhaven worker from this repo. Do not start CRM from this repo.

## Sign-in

Public HTTPS hits oauth2-proxy first, then Keycloak client `plane`, then Plane. After the first boot, complete Plane instance setup once while signed in as a realm `nms` user.

Redirect URIs on the client:

- `https://pm.newmarketsecurity.com/oauth2/callback`
- `https://pm.newmarketsecurity.com/auth/oidc/callback/` (reserved if Plane later enables native OIDC)

## Safety

Never commit passwords, cookie secrets, OIDC client secrets, or project contents. Postgres is not published. This stack must not bind host 80/443.
