ARG BASE_IMAGE=node:25-bookworm-slim

FROM ${BASE_IMAGE}

ARG COMMIT_HASH
ARG BUILD_TIME

WORKDIR /app

COPY . ./

ENV NEXT_TELEMETRY_DISABLED=1

RUN npm install npm -g

RUN npm install && npm cache clean --force
RUN chmod +x entrypoint.sh

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
ENV LOG_LEVEL=error
ENV PLT_MANAGEMENT_API=false
ENV PLT_SERVER_METRICS=false
ENV PLT_SERVER_HEALTH=false
ENV WORKERS=2
ENV BACKLOG=511
ENV NODE_ENV=production

RUN npm run build

ENTRYPOINT ["./entrypoint.sh"]

LABEL org.opencontainers.image.authors="Platformatic"
LABEL org.opencontainers.image.created="$BUILD_TIME"
LABEL org.opencontainers.image.revision="$COMMIT_HASH"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.source="https://github.com/platformatic/node-caged"
LABEL org.opencontainers.image.title="benchmarks/next"
LABEL org.opencontainers.image.description="Next.js benchmark app for standard vs pointer-compressed Node.js"
