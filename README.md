# FinPay GitOps (Argo CD + Helm + Kustomize)

Implements the full FinPay Lab architecture as Kubernetes workloads driven by
Argo CD (ADR-0007). This repo is the **GitOps source of truth** Argo CD points at.

## Layout

```
gitops/
├── charts/
│   ├── finpay-service/        # one reusable chart for all 8 business services
│   │   └── templates/service.yaml   # Deployment + Service + probes + env
│   └── infra/                 # postgres, kafka, redis, opensearch, keycloak,
│                               #   prometheus, grafana, otel-collector
├── apps/
│   ├── appproject.yaml              # Argo AppProject "finpay"
│   ├── application-infra.yaml       # Application -> charts/infra (finpay-infra ns)
│   ├── applicationset-services.yaml # ApplicationSet -> one Application per service
│   └── values/<service>.yaml       # per-service Helm values (port, image, env)
├── environments/
│   ├── dev/      # = base
│   ├── staging/  # = base
│   └── prod/     # pins infra targetRevision: prod
└── kustomization.yaml             # root: groups appproject + infra App + services AppSet
```

## Services & ports

| Service | Port | Needs |
|---|---|---|
| gateway | 8080 | redis, kafka, keycloak(issuer) |
| identity-service | 8081 | — |
| customer-service | 8082 | postgres (`customer_service`), kafka |
| transfer-service | 8085 | — |
| ledger-service | 8086 | — |
| notification-service | 8087 | — |
| observability | 8090 | — |
| infrastructure | 8091 | — |

Database-per-service: `customer-service` owns `customer_service` on the shared
Postgres (ADR-0005). Other services are stubs (no JPA/Kafka yet) and run as
healthy k8s workloads that export OTel/Prometheus.

## Apply

```bash
# 1. Boot the control plane (Argo CD) in any cluster, then point it at this repo:
kubectl apply -k gitops                       # AppProject + infra App + services ApplicationSet

# 2. Or per environment:
kubectl apply -k gitops/environments/prod

# 3. Argo reconciles:
#    - finpay-infra   namespace  -> postgres/kafka/redis/opensearch/keycloak/prom/grafana/otel
#    - finpay-services namespace -> 8 service Deployments (from ApplicationSet)
```

> Note: `applicationset-services.yaml` uses Go templates (`{{ .name }}`); Argo
> renders them. `kustomize build` passes them through as literal strings and
> validates the surrounding structure — do not run `kubectl apply` on the raw
> ApplicationSet without Argo.

## Image build (per service repo)

Each service repo has a `Dockerfile` (multi-stage, JDK 21, bakes `./gradlew
bootJar`). The `finpay-platform` composite-build submodule must be present at
build time (checked out as a git submodule in CI). CI builds
`finpaylab/<service>:<tag>` and the GitOps `values/<service>.yaml` pins the tag;
Argo rolls it out.

## Local (kind/k3d) smoke test

```bash
kind create cluster --name finpay
kubectl create ns argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -k gitops
```
