# Secure, Auditable Deployment Pipeline

A CI/CD pipeline for a Spring Boot application using GitHub Actions, Azure Container Registry (ACR), and Azure Kubernetes Service (AKS), with Cosign image signing for supply-chain security.

---

## Architecture Overview

```
push develop  →  1·Build & Scan → 2·Push & Sign [approval] → 3·Verify & Deploy → AKS dev
push staging  →  1·Build & Scan → 2·Push & Sign [approval] → 3·Verify & Deploy → AKS staging
push prod     →  1·Build & Scan → 2·Push & Sign [approval] → 3·Verify & Deploy → AKS prod
```

Promotion order is enforced by branch protection: `develop → staging → prod` only.

---

## Pipeline Jobs

### 1 · Build & Security Scan
- Builds the Docker image using the multistage [Dockerfile](Dockerfile).
- Saves the image as a tar artifact **before** scanning — the exact binary that is scanned is the one deployed.
- Runs **Trivy** scanning for `CRITICAL` vulnerabilities only. Any finding fails the pipeline immediately, before any registry interaction.

### 2 · Push & Sign
- Gated by a **GitHub Environment approval** — a human reviewer must approve before the image is pushed.
- Authenticates to Azure via **Federated Identity (OIDC)** — no client secrets stored anywhere.
- Pushes the scanned image to ACR and captures the **immutable digest** (`sha256:...`).
- Signs the digest with **Cosign keyless signing**: an ephemeral certificate is issued by Sigstore Fulcio encoding the workflow identity. No private key is stored.

### 3 · Verify & Deploy
- Runs in a **separate job context** with no shared state from the signing job.
- Verifies the Cosign signature against the digest, anchored to this specific workflow file and the GitHub Actions OIDC issuer. A manually pushed image will have no valid signature and will fail here.
- Fetches AKS credentials and deploys with `helm upgrade --install`.
- Confirms the rollout with `kubectl rollout status`.

---

## Security Properties

| Property | Mechanism |
|---|---|
| No credentials stored | Azure Federated Identity (OIDC) — short-lived tokens at runtime |
| Tamper-proof images | Signed by immutable digest, not by tag |
| Verified supply chain | `cosign verify` before every deploy, anchored to workflow identity |
| No critical CVEs in prod | Trivy blocks the pipeline before any push |
| Controlled promotion | Branch protection + `branch-protection.yml` enforce `dev → staging → prod` |
| Human gates | GitHub Environment required reviewers on `staging` and `prod` |

---

## Repository Structure

```
.github/
  workflows/
    pipeline.yml            # Main CI/CD pipeline (build, scan, sign, deploy)
    branch-protection.yml   # Enforces dev → staging → prod merge order
Dockerfile                  # Multistage build: JDK builder + JRE runtime
helm/
  myapp/
    Chart.yaml
    values.yaml             # Default values
    values-dev.yaml         # Dev overrides (low resources, DEBUG logging)
    values-staging.yaml     # Staging overrides (2 replicas, INFO logging)
    values-prod.yaml        # Prod overrides (3+ replicas, HPA, WARN logging)
    templates/
      deployment.yaml
      service.yaml
docs/
  cosign-explained.md       # How Cosign keyless signing works
  setup-guide.md            # One-time Azure and GitHub configuration
```

---

## Setup

See [docs/setup-guide.md](docs/setup-guide.md) for the full one-time configuration:

1. **Azure** — Create one App Registration per environment with Federated Identity credentials and assign ACR/AKS roles.
2. **GitHub Repository Variables** — `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
3. **GitHub Environments** — Create `develop`, `staging`, `prod` with required reviewers and per-environment variables (`AZURE_CLIENT_ID`, `ACR_NAME`, `ACR_LOGIN_SERVER`, `AKS_CLUSTER_NAME`, `AKS_RESOURCE_GROUP`, `K8S_NAMESPACE`, `HELM_VALUES_FILE`).
4. **Branch Protection Rules** — Require the `Enforce merge path` status check on `staging` and `prod` branches.

---

## Cosign

See [docs/cosign-explained.md](docs/cosign-explained.md) for a detailed explanation of keyless signing, what gets verified at each step, and why no private key needs to be stored.
