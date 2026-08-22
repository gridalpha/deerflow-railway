# deerflow-railway

Deployment files for running [DeerFlow](https://github.com/bytedance/deer-flow)
2.0 on [Railway](https://railway.com).

DeerFlow is ByteDance's open-source super-agent harness: a lead agent that plans,
searches the web, writes files, delegates to sub-agents and produces reports,
podcasts and slide decks through installable skills.

Upstream publishes container images but its production `docker-compose.yaml`
mounts `config.yaml`, `extensions_config.json` and the bundled `skills/`
directory into the Gateway at run time. Railway has no bind mounts, so this repo
bakes those in, and adds the edge proxy Railway's host-only router cannot
provide.

## What is here

| Path | Builds | Role |
|---|---|---|
| `gateway/` | `ghcr.io/bytedance/deer-flow-backend:latest` + config, skills, entrypoint | FastAPI Gateway and agent runtime, private |
| `proxy/` | `nginx:1.29-alpine` + a Railway-adapted copy of upstream's `nginx.conf` | public edge, splits one domain between the frontend and the Gateway |

The Next.js frontend runs straight from `ghcr.io/bytedance/deer-flow-frontend:latest`
and needs nothing from this repo.

Both images build from the **repo root** — set `RAILWAY_DOCKERFILE_PATH` to
`gateway/Dockerfile` or `proxy/Dockerfile` rather than a service root directory.

## Gateway

`gateway/config.yaml` is upstream's `config.example.yaml` (config version 14)
with five changes:

- **Three model entries** — an OpenAI-compatible one (which also covers DeepSeek,
  OpenRouter, Groq, Volcengine and vLLM), Anthropic, and Gemini. Set the API key
  of whichever provider you use; models are only constructed when a run selects
  one, so the unused entries never block startup.
- **`database.backend: postgres`** so users, threads, checkpoints and run events
  live in Postgres rather than a SQLite file, and `run_events.backend: db`.
- **`memory.storage_path: .deer-flow/memory.json`** — upstream's default resolves
  under `/app/backend`, which is the container layer and is thrown away on every
  deploy.
- **A `checkpointer` section alongside `database`**, both on the same Postgres.
  `make_store()` is the one consumer that never learned about the unified
  `database` section: it reads `checkpointer` and nothing else, so without it
  the LangGraph Store silently falls back to `InMemoryStore` and every thread
  vanishes on restart, on a green deployment.
- **`sandbox.use: LocalSandboxProvider`** with `allow_host_bash: false`. The
  container-based AIO sandbox needs a Docker socket or a Kubernetes provisioner,
  neither of which exists on Railway.

Every `$VAR` in that file is resolved from the environment at load time and an
unset one raises at boot, so each has a default on the Railway service.

`gateway/entrypoint.sh` binds `$PORT` and, when `DEERFLOW_ADMIN_EMAIL` and
`DEERFLOW_ADMIN_PASSWORD` are set, seeds the first admin by POSTing to the
Gateway's own `/api/v1/auth/initialize` once it is healthy. A fresh DeerFlow has
no accounts and whoever reaches `/setup` first becomes admin, so on a public URL
that window is a race. The endpoint answers 409 once an admin exists, which
makes the seeder idempotent across redeploys.

### Skills

The published Gateway image contains no `skills/` directory — upstream ships the
22 bundled skills (`deep-research`, `ppt-generation`, `podcast-generation`,
`chart-visualization`, …) in the git repo and bind-mounts them. The Dockerfile
fetches them from the release tarball at `DEERFLOW_SKILLS_REF`, which must stay
on the tag the image was built from. `latest` is currently `v2.0.0`; bump both
together.

## Proxy

`proxy/nginx.conf.template` is upstream's `docker/nginx/nginx.conf` with the
changes Railway forces:

- listens on `$PORT`, and takes its `resolver` from `/etc/resolv.conf` with IPv6
  left on, since `*.railway.internal` resolves AAAA
- upstream hosts come from `GATEWAY_UPSTREAM` / `FRONTEND_UPSTREAM`, so they
  re-resolve per request and survive a redeploy behind them; each falls back on
  the value's *shape*, because a `${{svc.RAILWAY_PRIVATE_DOMAIN}}` reference
  renders empty until that service owns a deployment
- `/healthz` answers in this service instead of proxying, so its health check
  tests itself rather than an upstream that may not exist yet
- the `/api/sandboxes` location is dropped — that provisioner is Kubernetes-only
- `POST /api/v1/auth/register` returns 403 unless `DEERFLOW_ALLOW_REGISTRATION`
  is `true`. DeerFlow 2.0.0 has no server-side registration switch (upstream
  added `auth.local.allow_registration` after the release), so on a public URL
  that endpoint hands any visitor an account that spends the deployer's model
  credits.

## Variables

### Gateway

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `8001` | set by Railway |
| `DATABASE_URL` | — | `${{Postgres.DATABASE_URL}}` |
| `AUTH_JWT_SECRET` | — | signs session tokens; must stay stable or everyone is logged out |
| `LLM_MODEL` / `LLM_BASE_URL` / `LLM_API_KEY` | `gpt-5` / `https://api.openai.com/v1` / empty | any OpenAI-compatible endpoint |
| `ANTHROPIC_MODEL` / `ANTHROPIC_API_KEY` | `claude-sonnet-4-6` / empty | |
| `GEMINI_MODEL` / `GEMINI_API_KEY` | `gemini-2.5-flash` / empty | |
| `DEERFLOW_ADMIN_EMAIL` / `DEERFLOW_ADMIN_PASSWORD` | — | seeds the first admin at boot; at least 8 characters and a mixed character set |
| `DEER_FLOW_ENV` | `production` | also hard-disables `DEER_FLOW_AUTH_DISABLED` |
| `GATEWAY_ENABLE_DOCS` | `false` | Swagger UI, ReDoc and the OpenAPI schema |
| `GATEWAY_WORKERS` | `1` | the Gateway owns run state in process, and the Redis stream bridge that would allow more raises `NotImplementedError` in this release |
| `JINA_API_KEY`, `TAVILY_API_KEY`, `SERPER_API_KEY`, … | unset | optional search/crawl upgrades |

### Proxy

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `2026` | set by Railway |
| `GATEWAY_UPSTREAM` | `gateway.railway.internal:8001` | |
| `FRONTEND_UPSTREAM` | `frontend.railway.internal:3000` | |
| `DEERFLOW_ALLOW_REGISTRATION` | `false` | `true` opens `POST /api/v1/auth/register` |

### Frontend

| Variable | Notes |
|---|---|
| `PORT` | `3000` |
| `BETTER_AUTH_SECRET` | session signing, at least 32 characters |
| `DEER_FLOW_INTERNAL_GATEWAY_BASE_URL` | `http://gateway.railway.internal:8001` |
| `DEER_FLOW_TRUSTED_ORIGINS` | the public origin, e.g. `https://deerflow.up.railway.app` |

## Volume

Mount a volume on the Gateway at `/app/backend/.deer-flow`. It holds thread
workspaces, uploaded and agent-generated files, tool-result overflow and
long-term memory. Everything relational is in Postgres.

## Licence

DeerFlow is MIT-licensed by ByteDance. This repository only contains deployment
glue and carries no upstream source.

## assets/

`assets/deerflow-light.svg` is upstream's `frontend/public/images/deer.svg`
(MIT) with a light `fill` added on the root element. Upstream uses the mark as
a CSS mask, so it ships with no fill and renders black — invisible against
Railway's dark service tiles.
