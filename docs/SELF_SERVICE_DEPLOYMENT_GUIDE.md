# MOSIP Rapid Deployment — Self-Service Guide for QA / Dev Teams

**Version:** 1.0  
**Last updated:** July 2026  
**Audience:** New QA, dev, or platform team members with no prior MOSIP deployment experience  
**Scope:** AWS self-service rapid deployment using GitHub Actions automation  

---

## Document purpose

This guide explains how to deploy a full MOSIP environment **without DevOps in the loop** for most steps. It covers:

- Which **GitHub Actions workflows** to run (in order)
- Which **secrets and variables** to configure
- Which **DSF and Terraform files** to edit (and which you do **not** need to edit)
- What is still **manual** even with automation

> **Branch requirement:** Use a branch that includes the self-service automation workflows (for example `Ivanmeneges-patch-kubeconfig` or `develop` after PR merge). The plain `develop` branch **without** these workflows only supports the legacy manual path described in Appendix A.

---

## Table of contents

1. [Core concepts](#1-core-concepts)
2. [Deployment architecture](#2-deployment-architecture)
3. [One-time platform setup (DevOps)](#3-one-time-platform-setup-devops)
4. [Per-environment setup (QA / dev)](#4-per-environment-setup-qa--dev)
5. [Workflow reference — run in this order](#5-workflow-reference--run-in-this-order)
6. [Secrets and variables checklist](#6-secrets-and-variables-checklist)
7. [DSF and Terraform files — what to edit](#7-dsf-and-terraform-files--what-to-edit)
8. [Verification and sign-off](#8-verification-and-sign-off)
9. [Common mistakes](#9-common-mistakes)
10. [Appendix A — Legacy manual path (`develop` without automation)](#appendix-a--legacy-manual-path-develop-without-automation)
11. [Appendix B — Quick reference cheat sheet](#appendix-b--quick-reference-cheat-sheet)

---

## 1. Core concepts

### Branch = environment

Every workflow uses:

```yaml
environment: ${{ github.ref_name }}
```

So **your Git branch name is your GitHub Environment name**.

| Branch name | GitHub Environment | Example secrets location |
|-------------|-------------------|--------------------------|
| `qajava11` | `qajava11` | Settings → Environments → `qajava11` |
| `dev-int` | `dev-int` | Settings → Environments → `dev-int` |

To create a new environment: create a branch with that name (e.g. `qajava11`).

### Deployment profile

MOSIP rapid deployment uses **profiles** — a matched pair of Terraform + Helmsman config:

| Profile | Terraform tfvars | Helmsman DSF folder | Use case |
|---------|------------------|---------------------|----------|
| `mosip` | `terraform/.../infra/profiles/mosip/aws.tfvars` | `Helmsman/dsf/mosip-platform-1.2.0.x/` or `1.2.1.x/` | Full MOSIP platform |
| `esignet-standalone` | `terraform/.../infra/profiles/esignet-standalone/aws.tfvars` | `Helmsman/dsf/esignet-standalone/` | eSignet only |

Pick the MOSIP platform version folder (`1.2.0.x` vs `1.2.1.x`) to match your release.

### Automated vs manual

| Task | Self-service (automation branch) | Legacy (`develop` without automation) |
|------|----------------------------------|---------------------------------------|
| WireGuard peer allocation | **Workflow:** WireGuard onboard environment | Manual SSH to jump server |
| `TF_WG_CONFIG`, `CLUSTER_WIREGUARD_WG0/WG1` | Auto-published by wg-onboard | Manual copy to GitHub secrets |
| Rancher cluster registration | **Terraform:** `ENABLE_RANCHER_IMPORT=true` | Paste import URL in tfvars |
| Rancher group access (DEVOPS) | **Terraform:** `GRANT_RANCHER_DEVOPS_ACCESS=true` | Manual Rancher UI |
| `KUBECONFIG` secret | **Terraform:** `PUBLISH_KUBECONFIG=true` | Manual copy from Terraform output |
| DSF domain names | **Workflow inputs** + env vars (`${domain_name}`) | Search-replace `sandbox.xyz.net` in every DSF |
| Captcha keys | **Environment secrets** (`PREREG_CAPTCHA_*`, etc.) | Hardcoded in `external-dsf.yaml` hook |

---

## 2. Deployment architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 0 — One-time (DevOps)                                             │
│   Terraform base-infra  →  VPC + jump server + WireGuard server         │
│   (Optional) Keycloak-Rancher SAML Integration                          │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE 1 — Per environment (QA / dev)                                    │
│   1. Create branch (= env name)                                         │
│   2. Edit profile tfvars                                                │
│   3. WireGuard onboard workflow        → TF_WG_CONFIG, WG0, WG1          │
│   4. Set captcha secrets + env vars                                     │
│   5. Terraform infra workflow          → cluster + Rancher + KUBECONFIG │
│   6. Helmsman External workflow      → prereq + external DSF          │
│   7. Helmsman MOSIP (auto-triggered) → mosip DSF                      │
│   8. Helmsman Test Rigs (manual)     → testrigs DSF                   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Layer summary

| Layer | Creates | Workflow |
|-------|---------|----------|
| Base infra | VPC, jump server, WireGuard server | **terraform plan / apply** → `base-infra` |
| MOSIP infra | RKE2 cluster, nginx LB, DNS, external PostgreSQL | **terraform plan / apply** → `infra` |
| Helmsman prereq | Monitoring, Istio, logging | **Deploy External services… Helmsman** |
| Helmsman external | Keycloak, Kafka, MinIO, ActiveMQ, captcha | **Deploy External services… Helmsman** |
| Helmsman MOSIP | All MOSIP core services | **Deploy Mosip services… Helmsman** (auto) |
| Helmsman testrigs | API / UI / DSL test automation | **Deploy Testrigs… Helmsman** |

---

## 3. One-time platform setup (DevOps)

Perform these steps **once per organization / VPC**, before any QA team deploys.

### 3.1 Prerequisites

| Prerequisite | Notes |
|--------------|-------|
| AWS account + IAM credentials | For GitHub Actions |
| Route 53 hosted zone | e.g. `mosip.net` — note the `zone_id` |
| EC2 SSH key pair | e.g. `mosip-aws` — must match tfvars `ssh_key_name` |
| Ubuntu 24.04 AMI ID | For your AWS region |
| Existing VPC or new VPC via base-infra | `vpc_name` tag in tfvars |
| GPG passphrase | For Terraform local encrypted state |
| Rancher URL + API token | For cluster import automation |
| Self-hosted GitHub runner | Required for **WireGuard onboard** workflow (`runs-on: self-hosted`) |

### 3.2 Repository secrets (shared — set once)

Go to: **Repository → Settings → Secrets and variables → Actions → Repository secrets**

| Secret | Purpose |
|--------|---------|
| `GPG_PASSPHRASE` | Encrypt/decrypt Terraform local state |
| `AWS_ACCESS_KEY_ID` | AWS access |
| `AWS_SECRET_ACCESS_KEY` | AWS secret |
| `mosip-aws` (or your `ssh_key_name`) | **Full SSH private key** for EC2 nodes |
| `GH_INFRA_PAT` | Publish `KUBECONFIG`, trigger child Helmsman workflows |
| `ACTION_PAT` | WireGuard onboard — write environment secrets |
| `MOSIP_AWS_PEM` | WireGuard onboard — SSH key for jump server |

> **Tip:** Set SSH keys from file, not paste:  
> `gh secret set MOSIP_AWS_PEM --repo ORG/infra < ~/pem/mosip-aws.pem`

### 3.3 Deploy base infrastructure

**Workflow:** `terraform plan / apply`

| Input | Value |
|-------|-------|
| Branch | Your working branch (e.g. `develop` or platform branch) |
| `CLOUD_PROVIDER` | `aws` |
| `TERRAFORM_COMPONENT` | `base-infra` |
| `BACKEND_TYPE` | `local` (dev) or `remote` (prod) |
| `SSH_PRIVATE_KEY` | `mosip-aws` |
| `TERRAFORM_APPLY` | ✅ true |

**Edit before running:**  
`terraform/implementations/aws/base-infra/aws.tfvars`

| Variable | Example |
|----------|---------|
| `jumpserver_name` | `mosip-jump-01` |
| `mosip_email_id` | `admin@company.com` |
| `ssh_key_name` | `mosip-aws` |
| `jumpserver_ami_id` | Ubuntu 24.04 AMI for your region |
| `network_name` | `mosip-boxes` |
| `wireguard_peers` | `30` (peer pool size) |

**Output:** Jump server public IP — save this for WireGuard onboard workflow.

### 3.4 (Optional) Keycloak–Rancher SAML

**Workflow:** `Keycloak-Rancher SAML Integration`

Run once if you want Rancher SSO via Keycloak. Not required for a basic MOSIP deployment.

---

## 4. Per-environment setup (QA / dev)

Replace `qajava11` and `qajava11.mosip.net` with your environment name and domain throughout.

### Step 1 — Create deployment branch

```bash
git clone https://github.com/YOUR_ORG/infra.git
cd infra
git checkout <automation-branch>    # branch with self-service workflows
git pull
git checkout -b qajava11            # branch name = environment name
```

### Step 2 — Edit Terraform profile tfvars

**File:** `terraform/implementations/aws/infra/profiles/mosip/aws.tfvars`

| Variable | Replace with | Must match |
|----------|--------------|------------|
| `cluster_name` | `qajava11` | `env_name` in Helmsman workflows |
| `cluster_env_domain` | `qajava11.mosip.net` | `domain_name` in Helmsman workflows |
| `mosip_email_id` | your email | SSL cert notifications |
| `ssh_key_name` | `mosip-aws` | repo secret name |
| `zone_id` | Route53 zone ID | your hosted zone |
| `ami` | Ubuntu 24.04 AMI | your region |
| `vpc_name` | `mosip-boxes` | existing VPC |
| `enable_postgresql_setup` | `true` | external Postgres (recommended) |
| `nginx_node_ebs_volume_size_2` | `200` | required when external Postgres |
| `postgresql_port` | `5433` | `db_port` in Helmsman workflows |
| `k8s_infra_branch` | e.g. `develop` | k8s-infra repo branch |
| `mosip_infra_branch` | e.g. `develop` | mosip-infra repo branch |

Commit and push:

```bash
git add terraform/implementations/aws/infra/profiles/mosip/aws.tfvars
git commit -m "Configure tfvars for environment qajava11"
git push -u origin qajava11
```

> You do **not** need to set `rancher_import_url` in tfvars when using `ENABLE_RANCHER_IMPORT=true` — Terraform mints it automatically.

---

### Step 3 — WireGuard onboard (AUTOMATED)

**Workflow:** `WireGuard onboard environment`

> **Note:** `workflow_dispatch` workflows only show the **Run workflow** button when the workflow file exists on the repository **default branch**. Merge the workflow to `main`/`master`, or temporarily set your working branch as default for testing.

| Input | Value |
|-------|-------|
| Branch | `qajava11` |
| `ENV_NAME` | `qajava11` |
| `JUMPSERVER_HOST` | Jump server public IP from Step 3.3 |
| `WG_DIR` | `/home/ubuntu/wireguard_env_2026` |
| `ALLOWED_IPS` | `172.31.0.0/16` |
| `TICKET` | Optional, e.g. `DSD-10264` |
| `DRY_RUN` | `true` first (preview), then `false` (apply) |

**What this automates:**

| Action | Detail |
|--------|--------|
| SSH to jump server | Uses `MOSIP_AWS_PEM` repo secret |
| Allocate 3 free WireGuard peers | Distinct peers for TF + Helmsman wg0 + wg1 |
| Transform peer configs | Strips DNS line, sets `AllowedIPs` |
| Create GitHub Environment | Named `qajava11` |
| Publish environment secrets | `TF_WG_CONFIG`, `CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1` |

**No manual SSH peer editing required** unless this workflow fails.

---

### Step 4 — Captcha and environment configuration

#### 4a. Create reCAPTCHA keys (manual — Google has no API here)

Go to [Google reCAPTCHA Admin](https://www.google.com/recaptcha/admin/create) and create **reCAPTCHA v2** ("I'm not a robot") for:

| Domain | Secret names |
|--------|--------------|
| `prereg.qajava11.mosip.net` | `PREREG_CAPTCHA_SITE_KEY`, `PREREG_CAPTCHA_SECRET_KEY` |
| `admin.qajava11.mosip.net` | `ADMIN_CAPTCHA_SITE_KEY`, `ADMIN_CAPTCHA_SECRET_KEY` |
| `resident.qajava11.mosip.net` | `RESIDENT_CAPTCHA_SITE_KEY`, `RESIDENT_CAPTCHA_SECRET_KEY` |
| `esignet.qajava11.mosip.net` (if eSignet) | `ESIGNET_CAPTCHA_SITE_KEY`, `ESIGNET_CAPTCHA_SECRET_KEY` |

#### 4b. Set captcha environment secrets

**Settings → Environments → `qajava11` → Environment secrets**

```bash
gh secret set PREREG_CAPTCHA_SITE_KEY  --env qajava11 --repo YOUR_ORG/infra < prereg-site.key
gh secret set PREREG_CAPTCHA_SECRET_KEY --env qajava11 --repo YOUR_ORG/infra < prereg-secret.key
gh secret set ADMIN_CAPTCHA_SITE_KEY     --env qajava11 --repo YOUR_ORG/infra < admin-site.key
gh secret set ADMIN_CAPTCHA_SECRET_KEY   --env qajava11 --repo YOUR_ORG/infra < admin-secret.key
gh secret set RESIDENT_CAPTCHA_SITE_KEY  --env qajava11 --repo YOUR_ORG/infra < resident-site.key
gh secret set RESIDENT_CAPTCHA_SECRET_KEY --env qajava11 --repo YOUR_ORG/infra < resident-secret.key
```

Helmsman injects these into DSF at runtime — you do **not** hardcode keys in `external-dsf.yaml`.

#### 4c. Set GitHub Environment variables

**Settings → Environments → `qajava11` → Environment variables**

| Variable | Example | Used for |
|----------|---------|----------|
| `DOMAIN_NAME` | `qajava11.mosip.net` | `${domain_name}` in all DSF files |
| `ENV_NAME` | `qajava11` | Istio hook, global configmap |
| `CLUSTER_ID` | `c-8qqf6` | Rancher monitoring (`$CLUSTER_ID` in prereq DSF) |
| `DB_PORT` | `5433` | External PostgreSQL port |
| `ESIGNET_DB_PORT` | `5432` | eSignet standalone only |
| `SLACK_CHANNEL_NAME` | `#mosip-alerts` | Optional alerting |

> Get `CLUSTER_ID` from Rancher UI after first infra deploy, or set it before Helmsman if you know it from a prior environment pattern.

#### 4d. Set Rancher environment secrets (for Terraform automation)

**Settings → Environments → `qajava11` → Environment secrets**

| Secret | Example |
|--------|---------|
| `RANCHER_API_URL` | `https://rancher.mosip.net` |
| `RANCHER_API_TOKEN` | Rancher API token with cluster registration rights |

Optional environment variable:

| Variable | Example |
|----------|---------|
| `RANCHER_GROUP_PRINCIPAL_ID` | `keycloak_group://DEVOPS` |

---

### Step 5 — Terraform infra (AUTOMATED Rancher + KUBECONFIG)

**Workflow:** `terraform plan / apply`

| Input | Value |
|-------|-------|
| Branch | `qajava11` |
| `CLOUD_PROVIDER` | `aws` |
| `TERRAFORM_COMPONENT` | `infra` |
| `INFRA_PROFILE` | `mosip` |
| `BACKEND_TYPE` | `local` |
| `SSH_PRIVATE_KEY` | `mosip-aws` |
| `TERRAFORM_APPLY` | ✅ **true** |
| `ENABLE_RANCHER_IMPORT` | ✅ **true** |
| `PUBLISH_KUBECONFIG` | ✅ **true** (default) |
| `GRANT_RANCHER_DEVOPS_ACCESS` | ✅ **true** (default) |
| `RANCHER_DEVOPS_GROUP` | `DEVOPS` |
| `RANCHER_DEVOPS_ROLE` | `cluster-owner` |

**Prerequisite:** `TF_WG_CONFIG` must already exist (from Step 3).

**What Terraform workflow automates:**

| Step | Script | Replaces manual step |
|------|--------|----------------------|
| Mint Rancher import URL | `.github/scripts/rancher-register-cluster.sh` | Copy import YAML from Rancher UI |
| Grant DEVOPS group access | `.github/scripts/rancher-grant-cluster-access.sh` | Manual Rancher role binding |
| Publish `KUBECONFIG` | `.github/scripts/rancher-fetch-kubeconfig.sh` | Copy kubeconfig to GitHub secret |
| Apply QA RBAC in cluster | `qa-dev-rbac.yaml.tpl` | Giving everyone cluster-admin |

**After success:** Verify environment `qajava11` has secret `KUBECONFIG` (auto-published). Note your Rancher `CLUSTER_ID` for Step 6.

---

### Step 6 — Helmsman External (prereq + external)

**Workflow:** `Deploy External services of mosip using Helmsman`

| Input | Value |
|-------|-------|
| Branch | `qajava11` |
| `profile` | `mosip-platform-1.2.0.x` (match your MOSIP version) |
| `mode` | **`apply`** (NOT dry-run) |
| `domain_name` | `qajava11.mosip.net` |
| `env_name` | `qajava11` |
| `db_port` | `5433` |
| `esignet_db_port` | `5432` |
| `clusterid` | `c-8qqf6` (your Rancher cluster ID) |

**Deploys in parallel:**
- `Helmsman/dsf/mosip-platform-1.2.0.x/prereq-dsf.yaml` (Istio, monitoring, logging)
- `Helmsman/dsf/mosip-platform-1.2.0.x/external-dsf.yaml` (Keycloak, Kafka, MinIO, ActiveMQ, captcha)

**On success:** Automatically triggers **Helmsman MOSIP** workflow.

> **Always use `apply` mode.** Dry-run fails because shared configmaps/secrets across namespaces are not available during validation.

---

### Step 7 — Helmsman MOSIP (AUTOMATIC)

**Workflow:** `Deploy Mosip services of mosip using Helmsman`

Usually **auto-triggered** after Step 6 succeeds. If it does not start, run manually:

| Input | Value |
|-------|-------|
| Branch | `qajava11` |
| `profile` | `mosip-platform-1.2.0.x` |
| `mode` | **`apply`** |
| `domain_name` | `qajava11.mosip.net` |
| `env_name` | `qajava11` |
| `db_port` | `5433` |

**Deploys:** `Helmsman/dsf/mosip-platform-1.2.0.x/mosip-dsf.yaml`

---

### Step 8 — Helmsman Test Rigs (manual, optional)

Run only after **all MOSIP pods are Running**.

**Workflow:** `Deploy Testrigs of mosip using Helmsman`

| Input | Value |
|-------|-------|
| Branch | `qajava11` |
| `profile` | `mosip-platform-1.2.0.x` |
| `mode` | **`apply`** |
| `domain_name` | `qajava11.mosip.net` |
| `db_port` | `5433` |
| `env_name` | `qajava11` |

**Deploys:** `Helmsman/dsf/mosip-platform-1.2.0.x/testrigs-dsf.yaml`

---

## 5. Workflow reference — run in this order

| # | Workflow name | When | Who | Key inputs |
|---|---------------|------|-----|------------|
| 0 | `terraform plan / apply` | Once per VPC | DevOps | `base-infra`, apply=true |
| 1 | Create branch `qajava11` | Per env | QA/dev | — |
| 2 | Edit `profiles/mosip/aws.tfvars` | Per env | QA/dev | cluster_name, domain |
| 3 | `WireGuard onboard environment` | Per env | QA/dev | ENV_NAME, JUMPSERVER_HOST |
| 4 | Set captcha secrets + env vars | Per env | QA/dev | see Section 4 |
| 5 | `terraform plan / apply` | Per env | QA/dev | infra, mosip, ENABLE_RANCHER_IMPORT |
| 6 | `Deploy External services… Helmsman` | Per env | QA/dev | profile, domain_name, clusterid |
| 7 | `Deploy Mosip services… Helmsman` | Auto | — | profile, domain_name |
| 8 | `Deploy Testrigs… Helmsman` | Optional | QA/dev | profile, domain_name |

### Additional workflows

| Workflow | Purpose |
|----------|---------|
| `k8s_health_check` | Validate pod health across namespaces |
| `Keycloak-Rancher SAML Integration` | One-time Rancher SSO setup |
| `helmsman_esignet` | Deploy eSignet standalone profile |
| `helmsman_signup` | Deploy signup stack |
| `terraform-destroy` / Helmsman destroy workflows | Teardown — see `ENVIRONMENT_DESTRUCTION_GUIDE.md` |

---

## 6. Secrets and variables checklist

### Repository secrets (once)

- [ ] `GPG_PASSPHRASE`
- [ ] `AWS_ACCESS_KEY_ID`
- [ ] `AWS_SECRET_ACCESS_KEY`
- [ ] `mosip-aws` (SSH private key — name matches `ssh_key_name`)
- [ ] `GH_INFRA_PAT`
- [ ] `ACTION_PAT`
- [ ] `MOSIP_AWS_PEM`

### Environment secrets — `qajava11`

- [ ] `TF_WG_CONFIG` ← auto from WireGuard onboard
- [ ] `CLUSTER_WIREGUARD_WG0` ← auto from WireGuard onboard
- [ ] `CLUSTER_WIREGUARD_WG1` ← auto from WireGuard onboard
- [ ] `KUBECONFIG` ← auto from Terraform (`PUBLISH_KUBECONFIG=true`)
- [ ] `RANCHER_API_URL`
- [ ] `RANCHER_API_TOKEN`
- [ ] `PREREG_CAPTCHA_SITE_KEY` / `PREREG_CAPTCHA_SECRET_KEY`
- [ ] `ADMIN_CAPTCHA_SITE_KEY` / `ADMIN_CAPTCHA_SECRET_KEY`
- [ ] `RESIDENT_CAPTCHA_SITE_KEY` / `RESIDENT_CAPTCHA_SECRET_KEY`
- [ ] `SLACK_WEBHOOK_URL` (optional)

### Environment variables — `qajava11`

- [ ] `DOMAIN_NAME` = `qajava11.mosip.net`
- [ ] `ENV_NAME` = `qajava11`
- [ ] `CLUSTER_ID` = `c-xxxxx`
- [ ] `DB_PORT` = `5433`
- [ ] `ESIGNET_DB_PORT` = `5432`
- [ ] `SLACK_CHANNEL_NAME` (optional)
- [ ] `RANCHER_GROUP_PRINCIPAL_ID` (optional)

---

## 7. DSF and Terraform files — what to edit

### Terraform files

| File | When | Edit |
|------|------|------|
| `terraform/implementations/aws/base-infra/aws.tfvars` | Once per VPC | jumpserver, VPC, AMI, wireguard_peers |
| `terraform/implementations/aws/infra/profiles/mosip/aws.tfvars` | Per environment | cluster_name, domain, zone_id, vpc, postgres settings |

### DSF files (self-service path — minimal editing)

**Location:** `Helmsman/dsf/mosip-platform-1.2.0.x/` (or `1.2.1.x`)

| File | Auto-injected at runtime | Still edit manually |
|------|------------------------|---------------------|
| `prereq-dsf.yaml` | `${domain_name}`, `${env_name}`, `$CLUSTER_ID` | Chart versions (optional) |
| `external-dsf.yaml` | `${domain_name}`, `${db_port}`, captcha secrets | `postgresql.enabled` (must match tfvars) |
| `mosip-dsf.yaml` | `${domain_name}` throughout | Chart versions, partner-onboarder modules |
| `testrigs-dsf.yaml` | `${domain_name}` | Slack webhook (or use secret) |

**DSF placeholders (do NOT replace with hardcoded domains):**

```yaml
# Domain — resolved from workflow input domain_name or vars.DOMAIN_NAME
postgresHost: "postgres.${domain_name}"
kibanaHost: "kibana.${domain_name}"
istio.hosts[0]: "admin.${domain_name}"

# Environment — resolved from env_name or vars.ENV_NAME
postInstall: "$WORKDIR/hooks/install-istio-and-httpbin.sh ${domain_name} ${env_name}"

# Rancher cluster ID — resolved from CLUSTER_ID env var
grafana.global.cattle.clusterId: "$CLUSTER_ID"

# Captcha — resolved from environment secrets
postInstall: "$WORKDIR/hooks/captcha-setup.sh ${PREREG_CAPTCHA_SITE_KEY} ${PREREG_CAPTCHA_SECRET_KEY} ..."
```

### Shared utility file (edit once per MOSIP version)

| File | What to set |
|------|-------------|
| `Helmsman/utils/config-server-values.yaml` | `gitRepo.version` e.g. `release-1.2.4.4-RD` |

### PostgreSQL alignment

| Terraform `enable_postgresql_setup` | `external-dsf.yaml` `postgresql.enabled` |
|-------------------------------------|------------------------------------------|
| `true` (external Postgres via Terraform) | `false` |
| `false` (in-cluster Postgres) | `true` |

---

## 8. Verification and sign-off

### After Terraform infra

```bash
# Via Rancher UI or kubectl (after WireGuard connected):
kubectl get nodes
kubectl get namespaces
```

- [ ] All nodes `Ready`
- [ ] GitHub environment has `KUBECONFIG` secret
- [ ] Cluster visible in Rancher
- [ ] DEVOPS group has cluster access

### After Helmsman External

```bash
kubectl get pods -n istio-system
kubectl get pods -n cattle-monitoring-system
kubectl get pods -n keycloak
kubectl get pods -n kafka
kubectl get pods -n minio
```

- [ ] All pods `Running` or `Completed`

### After Helmsman MOSIP

```bash
kubectl get pods -n mosip
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed
```

- [ ] All core MOSIP pods `Running`
- [ ] Partner onboarder job `Completed` — check MinIO reports (see `ONBOARDING_GUIDE.md`)

### URL checks

| Service | URL |
|---------|-----|
| Keycloak | `https://iam.qajava11.mosip.net/auth` |
| Admin portal | `https://admin.qajava11.mosip.net` |
| Pre-registration | `https://prereg.qajava11.mosip.net` |
| Resident | `https://resident.qajava11.mosip.net` |
| Landing page | `https://qajava11.mosip.net` |

### QA sign-off checklist

```
[ ] Branch qajava11 created and pushed
[ ] profiles/mosip/aws.tfvars configured
[ ] WireGuard onboard completed (3 secrets present)
[ ] Captcha secrets set (6 keys)
[ ] Environment variables set (DOMAIN_NAME, ENV_NAME, CLUSTER_ID, DB_PORT)
[ ] Terraform infra apply succeeded
[ ] KUBECONFIG auto-published
[ ] Helmsman External apply succeeded
[ ] Helmsman MOSIP apply succeeded
[ ] All pods Running
[ ] Portals accessible via browser
[ ] Test rigs deployed (if required)
```

---

## 9. Common mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Branch name ≠ GitHub Environment name | "Secret not found" | Rename environment or branch to match |
| Skipped WireGuard onboard | Terraform infra fails on `TF_WG_CONFIG` | Run WireGuard onboard workflow first |
| `ENABLE_RANCHER_IMPORT=false` | No auto KUBECONFIG, manual Rancher steps | Enable import + set Rancher secrets |
| Used Helmsman `dry-run` | Validation errors, missing namespaces | Always use `apply` |
| Hardcoded domains in DSF on automation branch | Wrong hosts deployed | Use `${domain_name}` placeholders + workflow inputs |
| `postgresql.enabled` mismatch | Double Postgres or connection failures | Align with `enable_postgresql_setup` in tfvars |
| Missing captcha secrets | Captcha broken on portals | Set all 6 captcha environment secrets |
| Wrong `CLUSTER_ID` | Grafana/monitoring broken | Copy correct ID from Rancher UI |
| Test rigs before MOSIP healthy | Test jobs fail immediately | Wait for all MOSIP pods Running |
| Workflow not visible in Actions | No "Run workflow" button | Merge workflow file to default branch |

---

## Appendix A — Legacy manual path (`develop` without automation)

Use this only if your branch does **not** have the self-service workflows.

| Step | Manual action |
|------|---------------|
| WireGuard | SSH to jump server, configure peers manually → `WIREGUARD_SETUP.md` |
| Secrets | Manually paste `TF_WG_CONFIG`, `CLUSTER_WIREGUARD_WG0/WG1`, `KUBECONFIG` |
| Rancher | Paste `rancher_import_url` in `infra/aws.tfvars` |
| DSF | Flat files in `Helmsman/dsf/` — search-replace `<sandbox>` and `sandbox.xyz.net` |
| Captcha | Hardcode keys in `external-dsf.yaml` activemq hook |
| Terraform tfvars | `terraform/implementations/aws/infra/aws.tfvars` (not profiles/) |

See also: `WORKFLOW_GUIDE.md`, `DSF_CONFIGURATION_GUIDE.md`

---

## Appendix B — Quick reference cheat sheet

### 10-step QA deployment

```
1.  git checkout -b <env-name>
2.  Edit profiles/mosip/aws.tfvars → push
3.  Run: WireGuard onboard environment (DRY_RUN=false)
4.  Set captcha secrets (6) on environment
5.  Set env vars: DOMAIN_NAME, ENV_NAME, CLUSTER_ID, DB_PORT
6.  Set Rancher secrets: RANCHER_API_URL, RANCHER_API_TOKEN
7.  Run: terraform plan/apply → infra, mosip, ENABLE_RANCHER_IMPORT=true
8.  Run: Deploy External services Helmsman → apply
9.  Wait: Deploy Mosip services Helmsman (auto)
10. Run: Deploy Testrigs Helmsman → apply (optional)
```

### Workflow → GitHub Actions sidebar name

| File | Name in Actions UI |
|------|-------------------|
| `terraform.yml` | terraform plan / apply |
| `wg-onboard.yml` | WireGuard onboard environment |
| `helmsman_external.yml` | Deploy External services of mosip using Helmsman |
| `helmsman_mosip.yml` | Deploy Mosip services of mosip using Helmsman |
| `helmsman_testrigs.yml` | Deploy Testrigs of mosip using Helmsman |
| `k8s_health_check.yml` | k8s health check |
| `keycloak-rancher-integration.yml` | Keycloak-Rancher SAML Integration |

### Related documentation

| Document | Topic |
|----------|-------|
| `SECRET_GENERATION_GUIDE.md` | How to create SSH keys, AWS creds |
| `RECAPTCHA_SETUP_GUIDE.md` | reCAPTCHA key creation |
| `ONBOARDING_GUIDE.md` | Partner onboarding failures |
| `ENVIRONMENT_DESTRUCTION_GUIDE.md` | Safe teardown |
| `HELMSMAN_EXTERNAL_GUIDE.md` | External DSF details |
| `HELMSMAN_MOSIP_GUIDE.md` | MOSIP DSF details |
| `TERRAFORM_WORKFLOW_GUIDE.md` | Terraform workflow parameters |
| `terraform/base-infra/WIREGUARD_SETUP.md` | Manual WireGuard (legacy) |

---

**End of document**

*MOSIP Infrastructure — Self-Service Rapid Deployment Guide*
