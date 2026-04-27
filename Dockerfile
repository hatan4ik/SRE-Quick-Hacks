# ── Stage 1: production dependencies ────────────────────────────
FROM node:16-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ── Stage 2: build (TypeScript / bundler) ───────────────────────
FROM node:16-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ── Stage 3: production runtime ─────────────────────────────────
FROM node:16-alpine AS runtime

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