# Setup Guide

One-time configuration needed before the pipeline can run.

---

## 1. Azure — Federated Identity (OIDC)

No client secrets are used.  GitHub Actions exchanges its built-in OIDC token
for a short-lived Azure AD access token at runtime.

### 1a. Create one App Registration per environment

| Environment | App Registration name       |
|-------------|-----------------------------|
| develop     | `myapp-github-oidc-dev`     |
| staging     | `myapp-github-oidc-staging` |
| prod        | `myapp-github-oidc-prod`    |

For each App Registration add a **Federated credential**:

```
Issuer:   https://token.actions.githubusercontent.com
Subject:  repo:<org>/<repo>:ref:refs/heads/<branch>
          e.g. repo:myorg/myrepo:ref:refs/heads/develop
Audience: api://AzureADTokenExchange
```

### 1b. Assign roles to each App Registration

| Resource         | Role                  | Why                          |
|------------------|-----------------------|------------------------------|
| ACR (own env)    | `AcrPush`             | Push images + Cosign OCI artifacts |
| ACR (prev env)   | `AcrPull`             | `az acr import` source access (staging needs AcrPull on dev-ACR; prod on staging-ACR) |
| AKS cluster      | `Azure Kubernetes Service Cluster User Role` | `az aks get-credentials` |
| AKS cluster      | `Azure Kubernetes Service RBAC Writer` (per namespace) | `kubectl` / Helm deploy |

---

## 2. GitHub — Repository Variables

Settings → Secrets and variables → Actions → **Variables** tab

| Variable name          | Example value              |
|------------------------|----------------------------|
| `AZURE_TENANT_ID`      | `xxxxxxxx-xxxx-xxxx-...`   |
| `AZURE_SUBSCRIPTION_ID`| `yyyyyyyy-yyyy-yyyy-...`   |

---

## 3. GitHub — Environments

Settings → Environments → New environment.  Create three:

| Environment | Required reviewers | Deployment branch rule |
|-------------|--------------------|------------------------|
| `develop`   | optional           | `develop`              |
| `staging`   | ✅ 1+ reviewer     | `staging`              |
| `prod`      | ✅ 1+ reviewer     | `prod`                 |

For each environment add these **Environment variables**:

| Variable           | develop                       | staging                        | prod                        |
|--------------------|-------------------------------|--------------------------------|-----------------------------|
| `AZURE_CLIENT_ID`  | `<app-reg-dev-client-id>`     | `<app-reg-staging-client-id>`  | `<app-reg-prod-client-id>`  |
| `ACR_NAME`         | `mycompanyacr-dev`            | `mycompanyacr-staging`         | `mycompanyacr-prod`         |
| `ACR_LOGIN_SERVER` | `mycompanyacr-dev.azurecr.io` | `mycompanyacr-staging.azurecr.io` | `mycompanyacr-prod.azurecr.io` |
| `AKS_CLUSTER_NAME` | `aks-dev`                     | `aks-staging`                  | `aks-prod`                  |
| `AKS_RESOURCE_GROUP`| `rg-dev`                    | `rg-staging`                   | `rg-prod`                   |
| `K8S_NAMESPACE`    | `dev`                         | `staging`                      | `prod`                      |
| `HELM_VALUES_FILE` | `values-dev.yaml`             | `values-staging.yaml`          | `values-prod.yaml`          |
| `SOURCE_ACR_LOGIN_SERVER` | *(n/a)*              | `mycompanyacr-dev.azurecr.io`  | `mycompanyacr-staging.azurecr.io` |
| `SOURCE_ACR_RESOURCE_ID`  | *(n/a)*              | `/subscriptions/.../registries/mycompanyacr-dev` | `/subscriptions/.../registries/mycompanyacr-staging` |

---

## 4. Branch Protection Rules

Settings → Branches → Add branch ruleset for each protected branch.

### `staging` branch

- **Require a pull request before merging**
- **Allowed merge sources:** only `develop` (use "Restrict pushes that create
  matching branches" or a PR-source check via a GitHub Action)
- **Require status checks:** `Build & Security Scan`
- **Dismiss stale reviews on new commits**

### `prod` branch

Same as above, but **Allowed merge sources:** only `staging`.

> Tip: enforce the source-branch restriction with a GitHub Actions check that
> reads `github.base_ref` and `github.head_ref` and fails the PR if the
> source branch is not the expected one:
>
> ```yaml
> - name: Enforce merge path
>   run: |
>     if [[ "${{ github.base_ref }}" == "staging" && "${{ github.head_ref }}" != "develop" ]]; then
>       echo "staging only accepts PRs from develop"; exit 1
>     fi
>     if [[ "${{ github.base_ref }}" == "prod" && "${{ github.head_ref }}" != "staging" ]]; then
>       echo "prod only accepts PRs from staging"; exit 1
>     fi
> ```
