# druk-keys

Public key distribution service for Druk identity services. Serves an RSA-2048
signing key as a JWKS (RFC 7517) at `/protocol/openid-connect/certs`, deployable
as a static site to GitHub Pages. Key lifecycle is managed entirely inside
Docker; only the public key material ever leaves this machine.

## Layout

- `scripts/gen-keys.mjs` — RSA-2048 keypair → `generated/private.pem` + `generated/certs`
- `Dockerfile.build` — assembles `dist/` (site + JWKS + `.nojekyll`) for Pages
- `Dockerfile.deploy` + `deploy-entry.sh` — git-push `dist/` to the Pages branch, enable Pages via API
- `docker-compose.yml` — `keygen`, `serve`, `build`, `deploy`
- `nginx.conf` — local hosting of the same site (port 9999) for pre-deploy testing

## 1. Prerequisites

- Docker + compose
- A GitHub account and a repo (public on the free plan)
- A GitHub token: Settings → Developer settings → Personal access tokens (classic),
  scope `repo` (or fine-grained with Contents RW + Pages RW on the repo)
- `cp .env.example .env` and fill `GITHUB_TOKEN` + `GITHUB_REPO`

## 2. Generate keys (once)

```sh
docker compose run --rm keygen
# KID=other-key docker compose run --rm keygen
# ROTATE=1 docker compose run --rm keygen   # force regenerate
```

`generated/private.pem` must NEVER leave this machine and is not in git.

## 3. Local test (no cloud needed)

```sh
docker compose up serve          # site on http://localhost:9999
curl -s http://localhost:9999/protocol/openid-connect/certs
```

## 4. Deploy to GitHub Pages

```sh
docker compose run --rm --build build   # refresh dist/
docker compose run --rm deploy          # push dist/ to gh-pages + enable Pages
```

The deploy step prints the base URL:

```
https://<owner>.github.io/<repo>/protocol/openid-connect/certs
```

## Rotation

```sh
ROTATE=1 docker compose run --rm keygen
docker compose run --rm --build build && docker compose run --rm deploy
```

Tokens signed with the previous private key stop verifying after the redeploy —
intended.

## Notes

- GitHub Pages serves static files only; Docker is purely the build/deploy pipeline.
- Pages serves the extensionless `certs` file as `application/octet-stream`;
  consumers that parse the body as JSON (e.g. jwks-rsa) are unaffected.
- The deployed site and key set are public by design; they contain no secrets.
- The `kid` in the JWKS must match the `kid` header of tokens signed with the
  corresponding private key (default `druk-key-1`).
