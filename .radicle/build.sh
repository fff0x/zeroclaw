#!/usr/bin/env bash
# Build, push and sign this repo's container image. Run by radicle-native-ci inside
# the radicle/ci-broker container. Ported from the central SourceHut images/.build.yml
# (docker buildx -> buildah); the image name is read from ARG CAT= / ARG APP= in the
# Dockerfile, so this script is identical across all image repos.
#
# Required env (from the broker's ci-broker-secrets Secret, via envFrom):
#   REGISTRY OCI_REG_USERNAME OCI_REG_PASSWORD COSIGN_KEY COSIGN_PASSWORD
# Optional:
#   ARCHES  space-separated arch list [default: "arm64 amd64"]. arm64 builds natively;
#           amd64 RUN steps are emulated via the kernel binfmt qemu handlers registered
#           fleet-wide by the kube-system `binfmt` DaemonSet. Set ARCHES="arm64" to skip
#           amd64 for an image that only runs in-cluster.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

: "${REGISTRY:?REGISTRY not set}"
: "${OCI_REG_USERNAME:?OCI_REG_USERNAME not set}"
: "${OCI_REG_PASSWORD:?OCI_REG_PASSWORD not set}"
: "${COSIGN_KEY:?COSIGN_KEY not set}"
: "${COSIGN_PASSWORD:?COSIGN_PASSWORD not set}"
export COSIGN_PASSWORD

read -r -a ARCHES <<< "${ARCHES:-arm64 amd64}"

# Vendored sources (e.g. snac/src, tmate/src) live in git submodules.
if [ -f .gitmodules ]; then
  echo ">> initializing submodules"
  git submodule update --init --recursive
fi

CAT="$(grep -Po '(?<=^ARG CAT=).*$' Dockerfile | head -n1 | tr -d ' \r')"
APP="$(grep -Po '(?<=^ARG APP=).*$' Dockerfile | head -n1 | tr -d ' \r')"
[ -n "${CAT}" ] && [ -n "${APP}" ] || { echo "Dockerfile is missing ARG CAT= / ARG APP=" >&2; exit 1; }
IMG="${CAT}/${APP}"
SHA="$(git rev-parse --short=7 HEAD)"
CREDS="${OCI_REG_USERNAME}:${OCI_REG_PASSWORD}"

echo "${OCI_REG_PASSWORD}" | buildah login --username "${OCI_REG_USERNAME}" --password-stdin "${REGISTRY}"
crane auth login "${REGISTRY}" -u "${OCI_REG_USERNAME}" -p "${OCI_REG_PASSWORD}"

COSIGN_PUB_KEY="$(mktemp)"
trap 'rm -f "${COSIGN_PUB_KEY}"' EXIT
cosign public-key --key "${COSIGN_KEY}" > "${COSIGN_PUB_KEY}"

echo ">> building ${IMG} for: ${ARCHES[*]}"
manifests=()
for arch in "${ARCHES[@]}"; do
  buildah bud --arch "${arch}" --layers -f Dockerfile -t "${REGISTRY}/${IMG}:build-${arch}" .
  buildah push --creds "${CREDS}" "${REGISTRY}/${IMG}:build-${arch}" "docker://${REGISTRY}/${IMG}:build-${arch}"
  manifests+=(--manifest "${REGISTRY}/${IMG}:build-${arch}")
done

for tag in "${SHA}" latest; do
  crane index append "${manifests[@]}" --tag "${REGISTRY}/${IMG}:${tag}"
done

for tag in "${SHA}" latest; do
  digest="$(skopeo inspect --creds "${CREDS}" "docker://${REGISTRY}/${IMG}:${tag}" --format '{{.Digest}}')"
  echo ">> signing ${REGISTRY}/${IMG}@${digest} (tag ${tag})"
  cosign sign --yes --recursive --key "${COSIGN_KEY}" "${REGISTRY}/${IMG}@${digest}"
  cosign verify --key "${COSIGN_PUB_KEY}" "${REGISTRY}/${IMG}@${digest}"
done
