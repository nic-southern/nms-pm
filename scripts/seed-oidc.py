#!/usr/bin/env python3
"""Seed Windshift sso_providers for Keycloak realm nms.

Encrypts the OIDC client secret the same way Windshift does (HKDF-SHA256 +
AES-GCM, label windshift-sso-secret-encryption-v1) so Admin > Single Sign-On
can decrypt it after boot.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import hmac
import os
import secrets
import sys


HKDF_INFO = b"windshift-sso-secret-encryption-v1"
DEFAULT_ATTRIBUTE_MAPPING = (
    '{"email":"email","name":"name","given_name":"given_name",'
    '"family_name":"family_name","username":"preferred_username",'
    '"email_verified":"email_verified"}'
)


def hkdf_sha256(ikm: bytes, info: bytes, length: int = 32) -> bytes:
    prk = hmac.new(bytes(32), ikm, hashlib.sha256).digest()
    okm = b""
    block = b""
    counter = 1
    while len(okm) < length:
        block = hmac.new(prk, block + info + bytes([counter]), hashlib.sha256).digest()
        okm += block
        counter += 1
    return okm[:length]


def encrypt_secret(server_secret: str, plaintext: str) -> str:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    if not plaintext:
        return ""
    key = hkdf_sha256(server_secret.encode("utf-8"), HKDF_INFO, 32)
    nonce = secrets.token_bytes(12)
    ciphertext = AESGCM(key).encrypt(nonce, plaintext.encode("utf-8"), None)
    return base64.b64encode(nonce + ciphertext).decode("ascii")


def decrypt_secret(server_secret: str, encoded: str) -> str:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM

    if not encoded:
        return ""
    key = hkdf_sha256(server_secret.encode("utf-8"), HKDF_INFO, 32)
    data = base64.b64decode(encoded)
    nonce, ciphertext = data[:12], data[12:]
    return AESGCM(key).decrypt(nonce, ciphertext, None).decode("utf-8")


def env_required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value or value == "replace_me":
        raise SystemExit(f"{name} is not set")
    return value


def self_test() -> None:
    secret = "ci-not-a-real-sso-secret"
    plaintext = "ci-not-a-real-client-secret"
    encoded = encrypt_secret(secret, plaintext)
    if decrypt_secret(secret, encoded) != plaintext:
        raise SystemExit("encryption round-trip failed")
    if len(base64.b64decode(encoded)) <= 12:
        raise SystemExit("ciphertext too short")
    print("sso secret encryption round-trip ok")


def seed() -> None:
    import psycopg

    sso_secret = env_required("SSO_SECRET")
    client_secret = env_required("OIDC_CLIENT_SECRET")
    issuer = os.environ.get("OIDC_ISSUER", "https://auth.newmarketsecurity.com/realms/nms")
    client_id = os.environ.get("OIDC_CLIENT_ID", "pm")
    slug = os.environ.get("OIDC_SLUG", "nms")
    scopes = os.environ.get("OIDC_SCOPES", "openid email profile")
    name = os.environ.get("OIDC_PROVIDER_NAME", "New Market Security")
    encrypted = encrypt_secret(sso_secret, client_secret)

    host = os.environ.get("POSTGRES_HOST", "postgres")
    port = os.environ.get("POSTGRES_PORT", "5432")
    user = os.environ.get("POSTGRES_USER", "windshift")
    password = env_required("POSTGRES_PASSWORD")
    dbname = os.environ.get("POSTGRES_DB", "windshift")

    conn = psycopg.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        dbname=dbname,
        connect_timeout=10,
    )
    conn.autocommit = True
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass('public.sso_providers')")
        if cur.fetchone()[0] is None:
            raise SystemExit("sso_providers does not exist yet; wait for Windshift to migrate")
        cur.execute(
            """
            INSERT INTO sso_providers (
                slug, name, provider_type, enabled, is_default,
                issuer_url, client_id, client_secret_encrypted, scopes,
                auto_provision_users, require_verified_email,
                attribute_mapping, created_at, updated_at
            ) VALUES (
                %s, %s, 'oidc', true, true,
                %s, %s, %s, %s,
                true, true,
                %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
            ON CONFLICT (slug) DO UPDATE SET
                name = EXCLUDED.name,
                provider_type = 'oidc',
                enabled = true,
                is_default = true,
                issuer_url = EXCLUDED.issuer_url,
                client_id = EXCLUDED.client_id,
                client_secret_encrypted = EXCLUDED.client_secret_encrypted,
                scopes = EXCLUDED.scopes,
                auto_provision_users = true,
                require_verified_email = true,
                attribute_mapping = EXCLUDED.attribute_mapping,
                updated_at = CURRENT_TIMESTAMP
            """,
            (slug, name, issuer, client_id, encrypted, scopes, DEFAULT_ATTRIBUTE_MAPPING),
        )
        cur.execute("UPDATE sso_providers SET is_default = false WHERE slug <> %s", (slug,))
        cur.execute(
            "SELECT slug, enabled, is_default, issuer_url, client_id FROM sso_providers WHERE slug = %s",
            (slug,),
        )
        row = cur.fetchone()
    conn.close()
    print(
        f"seeded sso provider slug={row[0]} enabled={row[1]} default={row[2]} "
        f"issuer={row[3]} client_id={row[4]}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    seed()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
