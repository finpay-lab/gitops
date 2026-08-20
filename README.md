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
| identity-service | 8081 | postgres (`identity_service`), keycloak |
| customer-service | 8082 | postgres (`customer_service`), kafka |
| transfer-service | 8085 | postgres (`transfer_service`), kafka |
| ledger-service | 8086 | postgres (`finpay_ledger`), kafka |
| notification-service | 8087 | postgres (`finpay_notification`), kafka |
| observability | 8090 | prometheus, otel-collector |
| infra-tooling | 8091 | — (renamed from `infrastructure` to avoid shadowing `finpay-infra`) |

Database-per-service: `customer-service` owns `customer_service`, `ledger-service`
owns `finpay_ledger`, `transfer-service` owns `transfer_service`,
`identity-service` owns `identity_service`, `notification-service` owns
`finpay_notification` (ADR-0005). All 8 services are fully implemented (JPA +
Kafka + REST) and run as healthy k8s workloads exporting OTel/Prometheus.

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

Each service repo has a **runtime-only** `Dockerfile` that copies a pre-built
`build/libs/*.jar` into `eclipse-temurin:21-jre`. The `bootJar` is produced
separately with the Gradle image (keeps the image build fast + reproducible):

```bash
# 1. build the jar (finpay-platform submodule must be present on disk)
docker run --rm -v "$PWD":/work -w /work -v gradle-cache:/root/.gradle \
  gradle:9.7.0-jdk21-ubi gradle clean bootJar --no-daemon
# 2. build + tag the image
docker build -t finpaylab/<service>:<tag> .
# 3. load into a local kind cluster (no registry needed for the lab)
kind load docker-image finpaylab/<service>:<tag> --name finpay
```

CI does the same and pushes `finpaylab/<service>:<tag>` to a registry; the
GitOps `values/<service>.yaml` pins the tag and Argo rolls it out.

## Local (kind/k3d) smoke test

```bash
kind create cluster --name finpay
kubectl create ns argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -k gitops
```
