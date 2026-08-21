# ADR-0014: Platform Capabilities — Object Storage (MinIO) & Secret Management (Vault) + Test Website

Status: Proposed
Date: 2026-08-21

## Context

The FinPay Lab currently has compute (8 services), datastores (Postgres, Redis,
Kafka, OpenSearch), and observability (Prometheus, Grafana, OTel) — but no
**shared blob storage** and no **centralized secret management**. Two gaps block
several features:

- **Object storage** is needed for KYC documents (AI-6), statement PDFs, audit
  exports, and AI artifacts (RAG corpus, extracted fields). Today every service
  would have to own a store or stuff blobs in Postgres — violating clean
  boundaries and bloating the DB.
- **Secret management** is needed so the BYOK AI keys, DB/Kafka/Redis passwords,
  and the future GHCR pull secret are never hardcoded and are injected to pods
  from one place (AGENTS.md BYOK rule; SECURITY.md "never logged"). Today
  secrets are literals in gitops values — unacceptable for a production-oriented
  design.

We also need a **simple website** to exercise every feature end-to-end without
curl/Postman, validating that the platform actually works as a system.

Decisions below are for the **local kind lab**; each notes the production gap.

## Decision 1 — Object Storage: MinIO (S3-compatible)

- Deploy **MinIO** in `finpay-infra` (1 replica, RAM-limited to match the
  1-pod-per-service policy; document the prod gap: multi-node erasure coding).
- Services reach it via ClusterIP `minio.finpay-infra.svc.cluster.local:9000`
  (API) and `:9001` (console). If exposed externally, use firewall allow-list
  port **8091** (free).
- **Buckets** provisioned by config/IaC: `finpay-kyc`, `finpay-statements`,
  `finpay-audit`, `finpay-ai-artifacts`. Versioning on; short lifecycle
  (cheap disk).
- **Hexagonal access**: a `BlobStore` port in `domain/`, MinIO S3 impl in
  `infrastructure/` (shared `common-*` lib or per-service). Services never talk
  to MinIO directly.
- **Credentials from Vault** (Decision 2) — never hardcoded, never logged.
- GitOps: MinIO chart + values under `gitops/charts/infra`; image pinned,
  1 replica, resource limits.
- Tests: put/get/delete round-trip against MinIO; bucket-exists check.

## Decision 2 — Secret Management: HashiCorp Vault

- Deploy **Vault** in `finpay-infra` (dev/raft mode for the lab, 1 replica;
  document prod gap: HA raft + auto-unseal via KMS).
- Expose via ClusterIP `vault.finpay-infra.svc.cluster.local:8200`; UI/API on
  allow-list port **8091** if external.
- **Auth**: Kubernetes auth method → Vault issues short-lived, SA-bound dynamic
  secrets. Pods authenticate via **Vault Agent sidecar** (or CSI provider) and
  mount secrets as files/env. No plaintext in gitops values.
- **Engines**: KV v2 for static secrets (Postgres password, Kafka creds, Redis
  password, GHCR pull secret, BYOK AI key). Optionally DB dynamic creds for
  Postgres.
- **Bootstrap** (run-once, not in Argo sync loop): init KV v2, write bootstrap
  secrets from a one-time job — **never commit them**. Lab uses single-key
  auto-unseal; documented as a prod gap.
- **Rotation**: Vault lease renewal + rotation; AI keys rotated without pod
  restart where possible.
- **Audit**: Vault audit device on; every secret read logged; AI keys never
  logged (SECURITY.md).
- GitOps: Vault chart + auth-config + policy manifests under
  `gitops/charts/infra`. Service Deployments mount secrets via Vault Agent.
- Tests: a pod with Vault Agent sidecar mounts a KV secret and asserts the
  value at runtime; rotation re-read picks up the new value.

### Why Vault over Sealed Secrets
Sealed Secrets is GitOps-native and lower-friction, but it only encrypts static
values in git and offers no dynamic secrets, rotation, or audit. **Vault** is
the production-grade choice the user selected: dynamic/rotating secrets, K8s
auth, audit device, and a clear path to cloud KMS auto-unseal. The trade-off is
operational weight (a running Vault + bootstrap) — acceptable for a
production-oriented demo.

## Decision 3 — Test Website (finpay-web)

- New standalone repo **`finpay-web`** (or a static site in gitops), served as a
  `finpay-services` app, **1 replica**, tiny limit.
- Thin UI over the **gateway only** (`gateway:8080`, HTTP, opaque lab JWT from
  `lab_token.txt` as `Authorization: Bearer`; handles 401). No client-side
  business logic.
- Surfaces per feature:
  - Customer: create/list, view KYC state.
  - Transfer: initiate → SAGA (transfer → risk/guardrail → ledger →
    notification), see status.
  - Ledger: entries + AI explainer (AI-3).
  - Notification: generated (AI-2) messages.
  - Identity: KYC doc upload + extraction status (AI-6) — **needs MinIO (D1)
    + Vault (D2)** for the upload + AI-key flow.
  - Observability: links to Grafana/Prometheus; anomaly score (AI-4).
  - AI guardrail (AI-7) shown on raw request send.
- **Dependency order**: non-AI flows (customer/transfer/ledger/notification/
  observability) work first; KYC-upload needs D1+D2.
- Deploy via gitops (new app `finpay-web`, 1 replica, limits).

## Consequences

- Clean blob boundary: blobs leave Postgres; services depend on a `BlobStore`
  port, not MinIO.
- No static secrets in gitops; everything sourced from Vault at runtime with
  audit + rotation.
- The website gives a human-verifiable end-to-end path across all services.
- **Lab gaps (documented, not implemented here)**: MinIO/Vault are
  single-replica dev mode; external exposure needs firewall ports 8091 (MinIO
  console / Vault UI); CI/CD (GHCR pull) remains paused pending a GitHub PAT.

## Tracking

- FP-66 — PLT-1 Object storage (MinIO)
- FP-67 — PLT-2 Secret management (Vault)
- FP-68 — WEB-1 Test website
