# syntax=docker/dockerfile:1
# Dockerfile version: 0.0.18

# Image identity (read by .radicle/build.sh) — published as ${CAT}/${APP}
ARG CAT=zeroclaw
ARG APP=zeroclaw

# renovate: datasource=docker depName=ghcr.io/zeroclaw-labs/zeroclaw versioning=loose
ARG ZEROCLAW_V=v0.8.0
# v0.8.0 (stable, 2026-06-12) is a BREAKING release: schema V3 + per-agent on-disk layout.
# It carries the b3e0719 fix (runtime_profiles.<p>.strict_tool_parsing). The migration of the
# config + deployment layout is documented in docs/ZEROCLAW.md — do NOT bump this
# in isolation. The v0.8.0-debian image is multi-arch (amd64 + arm64), so the FROM below resolves
# on the arm64 Turing-RK1 cluster. Do NOT use the floating `beta`/`beta-debian` tag (stale).

# Tool versions — bump these to update (or use Renovate)
ARG KUBECTL_V=v1.36.0
ARG FLUX_V=v2.8.6
ARG HELM_V=v4.1.4
ARG KUSTOMIZE_V=v5.8.1
ARG YQ_V=v4.53.2
ARG SOPS_V=v3.12.2
ARG JQ_V=jq-1.8.1
ARG SKOPEO_V=v1.20.1
ARG CRANE_V=v0.21.5
ARG COSIGN_V=v2.5.0
# renovate: datasource=docker depName=ghcr.io/siderolabs/installer
ARG TALOSCTL_V=v1.13.3
# renovate: datasource=github-releases depName=cilium/cilium-cli
ARG CILIUM_CLI_V=v0.19.4
# renovate: datasource=github-releases depName=go-task/task
ARG TASK_V=v3.51.1
# renovate: datasource=npm depName=renovate
ARG RENOVATE_V=40.55.0
# renovate: datasource=github-releases depName=radicle-dev/radicle
ARG RADICLE_V=1.9.1

# Stage 1: Download tools
FROM docker.io/library/debian:bookworm-slim AS tools

ARG TARGETARCH
ARG KUBECTL_V FLUX_V HELM_V KUSTOMIZE_V YQ_V SOPS_V JQ_V SKOPEO_V CRANE_V COSIGN_V TALOSCTL_V CILIUM_CLI_V TASK_V

RUN apt-get update && apt-get install -y --no-install-recommends xz-utils curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tools

RUN curl -fsSL --retry 5 --retry-delay 2 -o kubectl \
  "https://dl.k8s.io/release/${KUBECTL_V}/bin/linux/${TARGETARCH}/kubectl" \
  && chmod 755 kubectl && ./kubectl version --client=true

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/fluxcd/flux2/releases/download/${FLUX_V}/flux_${FLUX_V#v}_linux_${TARGETARCH}.tar.gz" \
  | tar xz flux \
  && chmod 755 flux && ./flux version --client

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://get.helm.sh/helm-${HELM_V}-linux-${TARGETARCH}.tar.gz" \
  | tar xz --strip-components=1 "linux-${TARGETARCH}/helm" \
  && chmod 755 helm && ./helm version

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_V}/kustomize_${KUSTOMIZE_V}_linux_${TARGETARCH}.tar.gz" \
  | tar xz kustomize \
  && chmod 755 kustomize && ./kustomize version

RUN curl -fsSL --retry 5 --retry-delay 2 -o yq \
  "https://github.com/mikefarah/yq/releases/download/${YQ_V}/yq_linux_${TARGETARCH}" \
  && chmod 755 yq

RUN curl -fsSL --retry 5 --retry-delay 2 -o sops \
  "https://github.com/getsops/sops/releases/download/${SOPS_V}/sops-${SOPS_V}.linux.${TARGETARCH}" \
  && chmod 755 sops

RUN curl -fsSL --retry 5 --retry-delay 2 -o jq \
  "https://github.com/jqlang/jq/releases/download/${JQ_V}/jq-linux-${TARGETARCH}" \
  && chmod 755 jq

RUN curl -fsSL --retry 5 --retry-delay 2 -o skopeo \
  "https://github.com/lework/skopeo-binary/releases/download/${SKOPEO_V}/skopeo-linux-${TARGETARCH}" \
  && chmod 755 skopeo && ./skopeo --version

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/google/go-containerregistry/releases/download/${CRANE_V}/go-containerregistry_Linux_$([ "${TARGETARCH}" = "amd64" ] && echo "x86_64" || echo "arm64").tar.gz" \
  | tar xz crane \
  && chmod 755 crane && ./crane version

RUN curl -fsSL --retry 5 --retry-delay 2 -o cosign \
  "https://github.com/sigstore/cosign/releases/download/${COSIGN_V}/cosign-linux-${TARGETARCH}" \
  && chmod 755 cosign && ./cosign version

RUN curl -fsSL --retry 5 --retry-delay 2 -o talosctl \
  "https://github.com/siderolabs/talos/releases/download/${TALOSCTL_V}/talosctl-linux-${TARGETARCH}" \
  && chmod 755 talosctl && ./talosctl version --client

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_V}/cilium-linux-${TARGETARCH}.tar.gz" \
  | tar xz cilium \
  && chmod 755 cilium && ./cilium version --client

RUN curl -fsSL --retry 5 --retry-delay 2 \
  "https://github.com/go-task/task/releases/download/${TASK_V}/task_linux_${TARGETARCH}.tar.gz" \
  | tar xz task \
  && chmod 755 task && ./task --version

# Stage 1b: Radicle CLI (rad, git-remote-rad, radicle-node)
FROM docker.io/library/debian:bookworm-slim AS radicle

ARG RADICLE_V
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates xz-utils openssh-client \
  && rm -rf /var/lib/apt/lists/*

RUN arch="$(case "${TARGETARCH}" in amd64) echo x86_64 ;; arm64) echo aarch64 ;; *) echo "${TARGETARCH}" ;; esac)" \
  && curl -sSLf "https://radicle.dev/install" | sh -s -- --prefix=/usr/local --no-modify-path --version="${RADICLE_V}" \
  && rad --version \
  && test -x /usr/local/bin/git-remote-rad

# Stage 1c: Renovate (Node)
FROM docker.io/library/node:22-bookworm-slim AS renovate

ARG RENOVATE_V

RUN npm install -g "renovate@${RENOVATE_V}" \
  && renovate --version

# Stage 2: Final image
FROM ghcr.io/zeroclaw-labs/zeroclaw:${ZEROCLAW_V}-debian

ARG ZEROCLAW_USER=claw
ARG ZEROCLAW_UID=1001
ARG ZEROCLAW_GID=1001

LABEL org.opencontainers.image.title="zeroclaw" \
  org.opencontainers.image.description="ZeroClaw AI-Agent with GitOps Tooling for managing infrastructure" \
  org.opencontainers.image.source="https://this-is-fine.io" \
  org.opencontainers.image.vendor="this-is-fine"

USER root

RUN groupadd -g ${ZEROCLAW_GID} -r ${ZEROCLAW_USER} 2>/dev/null || true \
  && useradd -u ${ZEROCLAW_UID} -g ${ZEROCLAW_GID} -m -d /zeroclaw-data -s /bin/bash -r ${ZEROCLAW_USER} \
  && chown -R ${ZEROCLAW_UID}:${ZEROCLAW_GID} /zeroclaw-data

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates curl git less openssh-client python3 python3-pip python3-venv python-is-python3 rsync ripgrep \
  && rm -rf /var/lib/apt/lists/*

COPY --from=tools /tools/ /usr/local/bin/
COPY --from=radicle /usr/local/bin/rad /usr/local/bin/git-remote-rad /usr/local/bin/radicle-node /usr/local/bin/
COPY --from=radicle /usr/local/share/man /usr/local/share/man
COPY --from=renovate /usr/local/bin/node /usr/local/bin/node
COPY --from=renovate /usr/local/lib/node_modules /usr/local/lib/node_modules
# Symlink renovate CLIs (dist/, not bin/ — npm global layout)
RUN ln -sf ../lib/node_modules/renovate/dist/renovate.js /usr/local/bin/renovate \
  && ln -sf ../lib/node_modules/renovate/dist/config-validator.js /usr/local/bin/renovate-config-validator \
  && renovate --version

COPY hooks/pre-push /opt/zeroclaw/hooks/pre-push
RUN chmod 755 /opt/zeroclaw/hooks/pre-push

ENV LANG=C.UTF-8 \
  HOME=/zeroclaw-data \
  RADICLE_HOME=/zeroclaw-data/.radicle \
  GIT_CONFIG_GLOBAL=/zeroclaw-data/.gitconfig

WORKDIR /zeroclaw-data
USER ${ZEROCLAW_USER}
