# ADR-0013: Production Hardening & Quality-Gate Review (FP-29)

Status: Accepted
Date: 2026-08-20

## Context

The FinPay Lab demonstrates a fictional banking platform on a local kind cluster.
Before declaring the lab "complete," we review the production-oriented hardening
that a real deployment would require, and record what is already demonstrated vs.
what remains cloud/CI-specific.

## Decisions already demonstrated in the lab

- **Per-service database ownership** (ADR-0005): each service owns its Postgres DB.
- **SAGA + Outbox + eventual consistency** (ADR-0003) instead of 2PC.
- **Idempotency**: every financial operation and every Kafka consumer is idempotent
  by `eventId` (ledger `AnomalyEventConsumer` DLQ + poison handling, FP-15).
- **Retry / circuit-breaker** semantics on remote calls (Rule 8); LLM clients use
  bounded retry + off-mode fallback (FP-65).
- **Observability**: OTel traces/metrics + Prometheus rules + Grafana (FP-23).
- **AI guardrails**: gateway `RequestGuard` injection filter; LLM completions are
  audit-logged by call count only (never payloads/PII) (FP-64/65).
- **Kubernetes hardening**: probes (liveness/readiness), resource limits, and a
  default-deny NetworkPolicy with explicit allow rules (FP-27).

## Remaining production work (tracked separately, not in this local lab)

- **Cloud IaC**: Terraform VPC/EKS modules + Ansible bootstrap (FP-26) — scaffolded
  under `gitops/terraform/`; applied to a managed cluster, not kind.
- **Edge security**: WAF rules + mTLS between services + CI secret scanning (FP-27)
  require a real ingress/WAF and a CI pipeline (GitHub Actions / GitLab CI).
- **Load & chaos**: k6 baseline+spike script under `gitops/loadtest/` (FP-28);
  failure-injection (§37) exercised via `kubectl delete pod` in the lab.
- **Final quality-gate**: this review; plus JUnit/AssertJ suites per service and
  `./gradlew build` green across all repos (achieved this cycle).

## Consequences

The lab is a faithful architecture demo. The cloud/CI items above are deliberately
out of scope for a single-node kind cluster and live as artifacts + tracked tickets
until a real environment exists.
