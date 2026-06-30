# Deploying ZeroClaw on Kubernetes

A self-contained [kustomize](https://kustomize.io/) example that runs the
[ZeroClaw](https://oci.this-is-fine.io/zeroclaw/zeroclaw) agent daemon plus its
Scrapling web-fetch MCP sidecar.

This is a **minimal** example: one agent, an Ollama provider, an optional Matrix
channel, and the Scrapling MCP. The author's production deployment additionally wires
a fleet of cluster credentials — those are deliberately left out here (see *Optional
integrations*).

## Prerequisites

Create the `zeroclaw-secrets` Secret **before** applying — see
[`secrets.example.yaml`](secrets.example.yaml) for the schema (it is deliberately not
part of the kustomization so placeholders are never applied). Only `OLLAMA_API_KEY`
is strictly required; the `MATRIX_*` keys are needed only if you keep the Matrix
channel enabled.

## Quickstart

```sh
# ... create the zeroclaw-secrets Secret first ...
kubectl apply -k deploy
```

This creates the Deployment (init renders `config.toml` from the `zeroclaw-config`
ConfigMap via `envsubst`), a `ClusterIP` Service (health/metrics on `42617`), and a
5Gi `PersistentVolumeClaim` for agent state + memory.

## Verify the image signature

Images are signed with [cosign](https://docs.sigstore.dev/) using a fixed key —
[`cosign.pub`](cosign.pub). Verify before pulling/deploying:

```sh
cosign verify --key cosign.pub oci.this-is-fine.io/zeroclaw/zeroclaw:latest
```

If a copy was not published to a transparency log, add `--insecure-ignore-tlog`.

## Configure

| File              | Change                                                              |
| ----------------- | ------------------------------------------------------------------- |
| `zeroclaw.toml`   | provider/model, channels, cron jobs, risk + runtime profiles        |
| `secrets.example.yaml` | `OLLAMA_API_KEY` and (optional) `MATRIX_*` values              |
| `deployment.yaml` | pin the image tag; resource sizing                                  |
| `pvc.yaml`        | `storage` size and `storageClassName` if needed                     |

`$${VAR}` placeholders in `zeroclaw.toml` are filled from `zeroclaw-secrets` at start
by the init container — keep secret values out of the ConfigMap.

## Expose

The `zeroclaw` Service exposes `/health` and `/metrics` on `42617`. Scrape it with
Prometheus (the pod is already annotated). The Scrapling MCP on `:8000` is
pod-internal and not exposed.

## Optional integrations

The full agent can operate infrastructure if you add, as extra containers/volumes:

- a **radicle** `client-node` sidecar (image `oci.this-is-fine.io/radicle/node`) +
  identity Secret, for git-over-radicle workflows;
- a **Tailscale** userspace sidecar for reaching remote cluster APIs over a tailnet;
- **kubeconfig / Talos / SOPS-age** Secrets mounted into the daemon for cluster ops.

Grant only the access you actually want the agent to have — these turn a chat bot
into an operator.

## Use as a GitOps base

```yaml
resources:
  - https://your-git-host/zeroclaw//deploy?ref=main
```

## Uninstall

```sh
kubectl delete -k deploy
```

> The PVC (agent memory + sessions) is removed with it. Back up `/zeroclaw-data`
> first if you want to keep the agent's evolved memory.
