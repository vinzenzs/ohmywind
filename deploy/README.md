# Deploying the MCP server outside Hugging Face

`packages/hf-space/` is the Hugging Face Spaces wrapper. This directory is the
"different wrapper" the cloud-agnostic rule calls for: a plain OCI image and a
Helm chart, with `mcp-core` and `data-adapters` untouched.

## Image

```sh
make docker-build            # docker build -f deploy/docker/Dockerfile -t ohmywind-mcp:local .
make docker-run              # http://localhost:7860/healthz, /mcp, /api/v1/...
```

Published by `.github/workflows/container.yml` to `ghcr.io/<owner>/ohmywind-mcp`
(`latest` = main, `dev` = dev, `1.2.3` = tag `v1.2.3`, plus `sha-<short>`),
for `linux/amd64` and `linux/arm64`. Runs as uid 10001 on port 7860.

| Env var | Default | Purpose |
|---|---|---|
| `OPENWIND_ALLOWED_HOSTS` | `qdonnars-openwind-mcp.hf.space,mcp.ohmywind.fr` | Hosts accepted on `/mcp` (matched as host:port, `localhost:*` for local runs); others get 421 |
| `OPENWIND_API_TOKEN` | empty | Bearer token(s) required on `/mcp` (comma-separated for rotation); empty = open. Never covers the REST routes (public web bundle calls them) |
| `OPENWIND_TRUSTED_PROXY_HOPS` | `1` | `X-Forwarded-For` hops to trust for rate limiting |
| `OPENWIND_EDGE_SECRET` | empty | Shared secret presented by `packages/edge-proxy` |
| `OPENWIND_RATE_LIMIT_REQUESTS` / `_WINDOW_S` / `_MAX_IPS` | `30` / `60` / `5000` | Per-IP limit on the POST routes |
| `OPENWIND_FRAME_ANCESTORS` | `'none'` (image) | CSP `frame-ancestors` |
| `MARC_ATLAS_DIR`, `SHOM_C2D_DIR` | `/data/atlas` | Tidal atlas directory (see below) |

The tidal atlas dataset is private and not redistributable, so it is **not**
in the image. Mount it at `/data/atlas`; without it the server serves
Open-Meteo SMOC currents only (fine offshore, insufficient in narrow passes).

## Web app image

The React bundle (`packages/web`) behind nginx, for deployments that do not
use Cloudflare Pages. The backend URL is **compiled into the bundle** by Vite,
so it is a build argument and the image is specific to one backend:

```sh
WEB_API_BASE=https://mcp.example.org make docker-build-web
make docker-run-web          # http://localhost:8080
```

CI publishes `ghcr.io/<owner>/ohmywind-web` with the same tags as the server
image, built against the repo Variable `WEB_API_BASE` (default
`https://mcp.ohmywind.fr`) — set it on your fork to your own MCP host.
`deploy/docker/nginx.conf` mirrors Cloudflare's `_headers`/`_redirects`
(`sw.js` no-store, `/confidentialite` → 200, unknown paths → `404.html`);
keep the three in sync. Runs as uid 101 on port 8080.

## Helm chart

```sh
helm install ohmywind oci://ghcr.io/<owner>/charts/ohmywind-mcp --version 0.1.0 \
  --set config.allowedHosts='{mcp.example.org}' \
  --set ingress.enabled=true --set ingress.hosts[0].host=mcp.example.org
```

or from the checkout: `helm install ohmywind deploy/helm/ohmywind-mcp`.

Add the web app with `--set web.enabled=true --set web.ingress.enabled=true
--set web.ingress.hosts[0].host=ohmywind.example.org` (image built for the
MCP host you expose; the server's CORS policy already allows any origin).

Notable values (`deploy/helm/ohmywind-mcp/values.yaml` is fully commented):

- `config.allowedHosts` — must contain every hostname MCP clients use
  (`/healthz` and the REST routes are not guarded).
- `auth.token` / `auth.existingSecret` — key `OPENWIND_API_TOKEN`; makes `/mcp`
  require `Authorization: Bearer <token>`. Claude Code:
  `claude mcp add --transport http ohmywind https://mcp.example.org/mcp --header "Authorization: Bearer <token>"`.
- `edgeSecret.value` / `edgeSecret.existingSecret` — key `OPENWIND_EDGE_SECRET`.
- `atlas.enabled` + `atlas.existingClaim` — PVC populated by you, mounted read-only.
- `replicaCount` > 1 requires session affinity at the ingress: streamable-HTTP
  MCP sessions live in the pod that opened them.

`make helm-lint` runs what CI runs (lint + full render); CI additionally
validates the manifests with kubeconform and pushes the chart on `v*` tags.
