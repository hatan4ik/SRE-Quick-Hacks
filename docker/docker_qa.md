# Docker — Assessment Q&A

---

## CODING QUESTION

### Q1. Write a production-ready Dockerfile for a Node.js application

**Requirements typically asked:**
- Pinned base image (not `latest`)
- Multi-stage build to minimize image size
- Non-root user
- Proper layer caching for `node_modules`
- `NODE_ENV=production`
- Health check
- Correct signal handling (PID 1)

---

### Answer — Complete Production Dockerfile (Node.js / TypeScript)

```dockerfile
# ── Stage 1: production dependencies ────────────────────────────
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ── Stage 2: build (TypeScript / bundler) ───────────────────────
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── Stage 3: production runtime ─────────────────────────────────
FROM node:20-alpine AS runtime

# Update OS packages and add dumb-init for correct PID 1 / signal handling
RUN apk update && apk upgrade && apk add --no-cache dumb-init

ENV NODE_ENV=production
ENV PORT=3000

WORKDIR /app

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy only what the runtime needs
COPY --from=deps  --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=build --chown=appuser:appgroup /app/dist        ./dist
COPY --from=build --chown=appuser:appgroup /app/package.json ./

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

# dumb-init as PID 1 → forwards SIGTERM to node correctly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
```

---

### Why each decision matters

| Decision | Why |
|---|---|
| `node:20-alpine` not `node:latest` | Pinned = reproducible; alpine ≈ 50 MB vs 300 MB |
| Multi-stage build | Final image has no build tools, devDeps, or source TS |
| `COPY package*.json` before `COPY . .` | Layer cache: only busted when deps change, not on every source edit |
| `npm ci` not `npm install` | Deterministic: exact lockfile versions, fails if lockfile is stale |
| `--omit=dev` | Excludes devDependencies from runtime image |
| `adduser -S` | Non-root: limits blast radius if container is exploited |
| `USER appuser` before `EXPOSE`/`CMD` | No step after this runs as root |
| `dumb-init` as PID 1 | Node should not be PID 1; dumb-init reaps zombies and forwards signals |
| `HEALTHCHECK` | Docker/orchestrators can mark container unhealthy and restart it |
| `ENTRYPOINT` + `CMD` split | ENTRYPOINT = binary; CMD = overridable default args |

---

### .dockerignore (always required)

```
node_modules
dist
.git
.github
*.log
.env
.env.*
coverage
Dockerfile*
docker-compose*
README.md
```

Without `.dockerignore`, `COPY . .` sends `node_modules` (potentially GBs) to the build daemon on every build.

---

### Python variant (FastAPI / Flask)

```dockerfile
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app

FROM base AS deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM base AS runtime
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
COPY --from=deps /usr/local/lib/python3.12/site-packages \
                 /usr/local/lib/python3.12/site-packages
COPY --chown=appuser:appgroup . .
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
```

### Go variant (smallest possible image)

```dockerfile
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app ./cmd/app

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

---

## Key Concepts — Common Exam Traps

### COPY vs ADD

| | `COPY` | `ADD` |
|---|---|---|
| Basic file copy | ✅ | ✅ |
| Auto-extract `.tar.gz` | ❌ | ✅ |
| Fetch from URL | ❌ | ✅ |
| **Use** | Always prefer | Only when you need tar extraction |

`ADD` from URLs bypasses layer caching and is unpredictable. Use `COPY`.

### CMD vs ENTRYPOINT

```dockerfile
# Shell form — bad for signals (runs as /bin/sh -c "node server.js")
CMD node server.js

# Exec form — correct (PID 1 is node, receives SIGTERM directly)
CMD ["node", "server.js"]

# Combined — ENTRYPOINT is the binary, CMD is overridable args
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "dist/server.js"]
# docker run myimage dist/other.js  → overrides CMD only
```

### ENV vs ARG

| | `ARG` | `ENV` |
|---|---|---|
| Available at build time | ✅ | ✅ |
| Available at runtime | ❌ | ✅ |
| Visible in `docker inspect` | ❌ (after build) | ✅ |
| **Never use for secrets** | ARG values appear in build history | ENV values visible at runtime |

Use BuildKit secret mounts for build-time secrets:
```dockerfile
RUN --mount=type=secret,id=npmrc,target=/root/.npmrc npm ci
```

### Layer cache order — always put expensive/stable steps first

```dockerfile
# BAD — any source change busts npm install
COPY . .
RUN npm install

# GOOD — npm install only reruns when package.json changes
COPY package*.json ./
RUN npm install
COPY . .
```

### apt-get — always combine update + install in one layer

```dockerfile
# BAD — stale package index can be cached
RUN apt-get update
RUN apt-get install -y curl

# GOOD
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*
```

---

## Quick Reference

```bash
docker build -t myapp:1.0 .
docker build --target build -t myapp:debug .    # build specific stage
docker run -p 3000:3000 --read-only myapp:1.0   # read-only filesystem
docker history myapp:1.0                         # inspect layers + sizes
docker inspect <container>                       # full config/state JSON
docker logs <container> --follow
docker exec -it <container> sh
docker system df                                 # disk usage
```

**Debugging a container that exits immediately:**
1. `docker logs <container>` — check stderr
2. Check `CMD`/`ENTRYPOINT` — is the process actually running in foreground?
3. Check missing env vars, missing files, permission errors
4. Run interactively: `docker run -it --entrypoint sh myapp:1.0`

**Container can't connect to Postgres using `localhost`:**
`localhost` inside a container = the container itself. Use the Compose service name: `postgres:5432`.
