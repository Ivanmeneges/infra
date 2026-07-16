# Automation Improvements Guide

This document describes three guardrail improvements for MOSIP self-service deployment:

1. **DevOps approval gates** for GitHub Actions  
2. **Multi-team Rancher access** via JSON config (no extra workflow inputs)  
3. **WireGuard offboarding** with real cryptographic revocation and peer reuse  

---

## 1. DevOps approval gates

### Problem

Anyone with **write** access to the `infra` repo can run `workflow_dispatch` and deploy infrastructure or applications.

### Solution

Use **GitHub Environment protection rules** + `environment:` on workflow jobs.

| Who | What they can do |
|-----|------------------|
| QA/dev (write access) | Click **Run workflow**, fill inputs |
| Workflow | Pauses at the `environment:` job |
| DevOps reviewer | Approves or rejects in GitHub UI |
| After approval | Job continues (Terraform apply, Helmsman, etc.) |

### One-time setup per environment

**Workflow:** `Setup environment protection`

| Input | Example |
|-------|---------|
| `ENV_NAME` | `qajava11` |
| `DRY_RUN` | `true` first, then `false` |
| `REVIEWER_TEAMS` | `devops` (optional override) |

Or run locally:

```bash
chmod +x .github/scripts/setup-environment-protection.sh
.github/scripts/setup-environment-protection.sh \
  --env qajava11 \
  --repo YOUR_ORG/infra \
  --reviewer-teams devops \
  --dry-run

# Apply:
.github/scripts/setup-environment-protection.sh \
  --env qajava11 \
  --repo YOUR_ORG/infra \
  --reviewer-teams devops
```

Edit defaults in `.github/config/environment-protection.json`:

```json
{
  "reviewer_teams": ["devops"],
  "reviewer_users": [],
  "deployment_branches": ["qajava11"],
  "prevent_self_review": false,
  "wait_timer_minutes": 0
}
```

### Workflows that respect approval (use `environment:`)

| Workflow | Environment binding |
|----------|---------------------|
| `terraform plan / apply` | `${{ github.ref_name }}` |
| `WireGuard onboard environment` | `${{ inputs.ENV_NAME }}` |
| `WireGuard offboard environment` | `${{ inputs.ENV_NAME }}` |
| `Deploy External services… Helmsman` | `${{ github.ref_name }}` |
| `Deploy Mosip services… Helmsman` | `${{ github.ref_name }}` |
| `Deploy Testrigs… Helmsman` | `${{ github.ref_name }}` |

> **Note:** The workflow file must exist on the repository **default branch** for the Run workflow button to appear. Environment protection is configured per environment name.

---

## 2. Multi-team Rancher access (JSON array)

### Problem

Terraform workflow had single inputs `RANCHER_DEVOPS_GROUP` and `RANCHER_DEVOPS_ROLE` — adding QA, developers, etc. would require more YAML inputs.

### Solution

Grants are defined as a **JSON array** in:

- **Default:** `.github/config/rancher-access-grants.json` (committed to repo)  
- **Per-env override:** GitHub environment variable `RANCHER_ACCESS_GRANTS` (same JSON schema)

Terraform input `GRANT_RANCHER_ACCESS=true` runs `.github/scripts/rancher-grant-cluster-access-batch.sh`, which loops all entries.

### Example — multiple teams, different roles

```json
[
  {
    "group": "DEVOPS",
    "role": "cluster-owner",
    "principal_id": "keycloak_group://DEVOPS",
    "fix_misbound_user": true
  },
  {
    "group": "QA",
    "role": "cluster-member",
    "principal_id": "keycloak_group://QA"
  },
  {
    "group": "DEVELOPERS",
    "role": "cluster-member",
    "principal_id": "keycloak_group://DEVELOPERS"
  }
]
```

| Field | Description |
|-------|-------------|
| `group` | Keycloak / IdP group name in Rancher |
| `role` | Rancher role template: `cluster-owner`, `cluster-member`, etc. |
| `principal_id` | Full principal (recommended): `keycloak_group://GROUPNAME` |
| `fix_misbound_user` | Optional; run misbinding repair for DEVOPS-style groups |

### Per-environment override

For environment `qajava11`, set variable `RANCHER_ACCESS_GRANTS` with a JSON array (e.g. QA gets `cluster-member` only in QA envs). No workflow YAML changes needed.

### Removed workflow inputs

These are **removed** from `terraform.yml` (use JSON instead):

- ~~`RANCHER_DEVOPS_GROUP`~~
- ~~`RANCHER_DEVOPS_ROLE`~~
- ~~`GRANT_RANCHER_DEVOPS_ACCESS`~~ → renamed to `GRANT_RANCHER_ACCESS`

---

## 3. WireGuard offboarding and peer reuse

### Problem

Clearing `assigned.txt` only updates bookkeeping. Anyone who saved a `.conf` file can still connect because:

- The peer public key is still on the server's live `wg0` interface  
- The peer stanza remains in `wg0.conf`  
- Client private keys are unchanged  

### Solution

**Workflow:** `WireGuard offboard environment`  
**Script:** `.github/scripts/wg-offboard.sh`

For each peer assigned to the environment:

| Step | Action |
|------|--------|
| 1 | `wg set wg0 peer <pubkey> remove` on jumpserver (live revoke) |
| 2 | Remove `[Peer]` block from persistent `wg0.conf` |
| 3 | Delete client key files under `config/peerN/` |
| 4 | Clear `assigned.txt` lines for the environment |
| 5 | Delete GitHub secrets `TF_WG_CONFIG`, `CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1` |
| 6 | Update `wg-peer-allocation.tsv` tracker |

### Peer reuse

| Input | Behaviour |
|-------|-------------|
| `REGENERATE_PEERS=true` (default) | After revoke, same `peerN` slot gets **new keys** and a new server stanza — ready for the next `wg-onboard` |
| `REGENERATE_PEERS=false` | Slot is empty; `wg-onboard` recreates keys on next allocation |

Old `.conf` files become **permanently invalid** after step 1 (server no longer accepts that public key).

### Run offboard

| Input | Value |
|-------|-------|
| `ENV_NAME` | `qajava11` |
| `JUMPSERVER_HOST` | jump server IP |
| `DRY_RUN` | `true` first, then `false` |
| `REGENERATE_PEERS` | `true` (recommended) |
| `DELETE_ENVIRONMENT` | `false` (keep env for secrets/vars) or `true` (full cleanup) |

```bash
.github/scripts/wg-offboard.sh \
  --env qajava11 \
  --host 3.7.248.153 \
  --ssh-key ~/pem/mosip-aws.pem \
  --repo YOUR_ORG/infra \
  --regenerate-peers \
  --dry-run
```

### Typical lifecycle

```
wg-onboard (env A)  →  peers 4,5,6 allocated, secrets published
        ↓
env A decommissioned
        ↓
wg-offboard (env A) →  revoke on server, delete secrets, regenerate peer slots
        ↓
wg-onboard (env B)  →  may reuse peer4/5/6 with NEW keys for env B
```

---

## Quick reference

| Need | Workflow / file |
|------|-----------------|
| Require DevOps approval | `Setup environment protection` + `.github/config/environment-protection.json` |
| Add Rancher teams/roles | Edit `.github/config/rancher-access-grants.json` or `vars.RANCHER_ACCESS_GRANTS` |
| Revoke VPN access permanently | `WireGuard offboard environment` |
| Reallocate peer to new env | Offboard old env → onboard new env |

See also: [SELF_SERVICE_DEPLOYMENT_GUIDE.md](SELF_SERVICE_DEPLOYMENT_GUIDE.md)
