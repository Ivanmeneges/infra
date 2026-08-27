# Automation Improvements Guide

This document describes guardrail improvements for MOSIP self-service deployment:

1. **DevOps approval gates** for GitHub Actions  
2. **Multi-team Rancher access** via JSON config (no extra workflow inputs)  
3. **WireGuard offboarding** with real cryptographic revocation and peer reuse  
4. **Rancher grant reliability** — cache fix, resilient KUBECONFIG publish  

> **Reference branch:** [`testiv`](https://github.com/mosip/infra/tree/testiv) on `mosip/infra` uses the expanded 8-team Rancher catalog (see [Section 2](#2-multi-team-rancher-access-json-array)).

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

Grants use **four merge layers** (later layers override earlier for the same `group`):

| Layer | Source | Purpose |
|-------|--------|---------|
| 1 | `.github/config/rancher-access-grants.json` | DEVOPS `cluster-owner` by default; other groups `enabled: true/false` |
| 2 | `vars.RANCHER_ACCESS_GRANTS` | Per-env **patch** (merge by group — not full replace) |
| 3 | `vars.RANCHER_DEVOPS_ROLE` / `RANCHER_DEVOPS_ENABLED` | Quick DEVOPS-only override per env |
| 4 | **Terraform workflow UI** | Per-run team selection — highest priority |

When `ENABLE_RANCHER_IMPORT=true`, the workflow automatically runs `.github/scripts/rancher-grant-cluster-access.sh --apply-catalog` (DEVOPS cluster-owner from JSON by default). No separate grant checkbox.

### Workflow UI (when you run Terraform)

**DEVOPS cluster-owner is automatic** — not shown in the workflow UI. Every new env gets DEVOPS as owner from `rancher-access-grants.json`.

| Input | Default | Purpose |
|-------|---------|---------|
| `GRANT_GROUP_ACCESS` | ☐ false | Apply other teams per JSON + env vars |
| `RANCHER_CLUSTER_OWNER_GROUP_ENABLED` | ☐ false | Grant cluster-owner to named group |
| `RANCHER_CLUSTER_OWNER_GROUP` | (empty) | e.g. `QA` — DEVOPS stays owner too |

**Example — DEVOPS only (new env):** leave both options unchecked.

**Example — DEVOPS + QA member:** set env `RANCHER_ACCESS_GRANTS` = `[{"group":"QA","enabled":true}]`, check `GRANT_GROUP_ACCESS`.

**Example — DEVOPS + QA both owners:** enable `RANCHER_CLUSTER_OWNER_GROUP_ENABLED`, set group = `QA`.

### Example — repo defaults (DEVOPS on; QA/DEVELOPERS off)

```json
[
  {
    "group": "DEVOPS",
    "role": "cluster-owner",
    "enabled": true,
    "principal_id": "keycloak_group://DEVOPS",
    "fix_misbound_user": true
  },
  {
    "group": "QA",
    "role": "cluster-member",
    "enabled": false,
    "principal_id": "keycloak_group://QA"
  }
]
```

| Field | Description |
|-------|-------------|
| `group` | Keycloak / IdP group name in Rancher |
| `role` | Rancher role template: `cluster-owner`, `cluster-member`, etc. |
| `enabled` | `true` / `false` — `false` skips that group (default: `true`) |
| `principal_id` | Full principal (recommended): `keycloak_group://GROUPNAME` |
| `fix_misbound_user` | Optional; run misbinding repair for DEVOPS-style groups |

### Per-environment override (merge patch)

**Enable QA on `qajava11` only** — variable `RANCHER_ACCESS_GRANTS`:

```json
[{ "group": "QA", "enabled": true }]
```

**Change DEVOPS role for one env** — either:

```json
[{ "group": "DEVOPS", "role": "cluster-member" }]
```

or shortcut variable `RANCHER_DEVOPS_ROLE` = `cluster-member`.

**Disable DEVOPS grant for one env** — variable `RANCHER_DEVOPS_ENABLED` = `false`.

See `.github/config/README.md` for full workflow input reference.

### testiv branch catalog (8 teams)

On `mosip/infra` branch **`testiv`**, `.github/config/rancher-access-grants.json` includes MOSIP org teams with **custom Rancher role template IDs** (not just `cluster-member`):

| Group | Role on testiv |
|-------|----------------|
| DEVOPS | `cluster-owner` (always granted) |
| QA, DEV | `rt-jdzrj` |
| PM, PO, BA, TL+ARCHITECT | `rt-rgcq7` |
| AUTOMATION | `rt-89ntg` |

Enable all teams on one run: check **`GRANT_GROUP_ACCESS=true`** in the Terraform workflow. For a first deploy or when Rancher API is slow, leave it unchecked (DEVOPS only).

---

## 4. Rancher grant reliability and KUBECONFIG publish

### Problem (observed on testiv)

When `GRANT_GROUP_ACCESS=true`, the grant script applied RBAC for each team sequentially. An older bug used `json="$(fetch_cluster_bindings)"`, which ran the fetch in a subshell and **discarded the in-memory cache** — causing one 60-second Rancher API list call **per team** (8 teams ≈ 8 minutes of API load). Timeouts at team 7/8 left **`KUBECONFIG` unpublished** because the publish step ran only after a successful grant.

### Solution (in `rancher-grant-cluster-access.sh` + `terraform.yml`)

| Fix | Behaviour |
|-----|-----------|
| Binding cache in parent shell | One list call prefetched at batch start |
| Retry list API | Up to 5 attempts on transient failures |
| HTTP 409 on create | Treated as success if binding already exists |
| Grant step `continue-on-error: true` | Partial RBAC failure does not fail the workflow |
| Publish step `if: always()` | When Terraform apply succeeded, **KUBECONFIG is published even if grant timed out** |

### Operational guidance (testiv)

| Situation | Recommended inputs |
|-----------|-------------------|
| First infra deploy | `GRANT_GROUP_ACCESS=false`, `PUBLISH_KUBECONFIG=true` |
| Add team RBAC after cluster is stable | Re-run apply (no-op) with `GRANT_GROUP_ACCESS=true` |
| Grant timed out but cluster imported | Re-run with `GRANT_GROUP_ACCESS=false` — publish step backfills `KUBECONFIG` |
| Rancher not deployed | `ENABLE_RANCHER_IMPORT=false`, set `KUBECONFIG` manually from control plane |

Ensure `GH_INFRA_PAT` has **Secrets: Read and write** — see [SECRET_GENERATION_GUIDE.md](SECRET_GENERATION_GUIDE.md#4-github-personal-access-token-gh_infra_pat).

---

## 3. WireGuard offboarding and peer reuse

### Problem

Clearing `assigned.txt` only updates bookkeeping. Anyone who saved a `.conf` file can still connect because:

- The peer public key is still on the server's live `wg0` interface  
- The peer stanza remains in `wg0.conf`  
- Client private keys are unchanged  

### Solution

**Workflow:** `WireGuard offboard environment`  
**Script:** `.github/scripts/wg-env.sh offboard`

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
| `REGENERATE_PEERS=true` (workflow default) | After revoke, same `peerN` slot gets **new keys** and a new server stanza — ready for the next `wg-env.sh onboard` |
| `REGENERATE_PEERS=false` | Slot is empty; `wg-env.sh onboard` recreates keys on next allocation |

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
.github/scripts/wg-env.sh offboard \
  --env qajava11 \
  --host 3.7.248.153 \
  --ssh-key ~/pem/mosip-aws.pem \
  --repo YOUR_ORG/infra \
  --regenerate-peers \
  --dry-run
```

### Typical lifecycle

```
wg-env.sh onboard (env A)  →  peers 4,5,6 allocated, secrets published
        ↓
env A decommissioned
        ↓
wg-env.sh offboard (env A) →  revoke on server, delete secrets, regenerate peer slots
        ↓
wg-env.sh onboard (env B)  →  may reuse peer4/5/6 with NEW keys for env B
                      assigned.txt is rewritten in peer-number order (peer4
                      appears after peer3, not appended at the end of the file)
```

---

## Quick reference

| Need | Workflow / file |
|------|-----------------|
| Require DevOps approval | `Setup environment protection` + `.github/config/environment-protection.json` |
| Add Rancher teams/roles | Edit `.github/config/rancher-access-grants.json` or `vars.RANCHER_ACCESS_GRANTS` |
| Revoke VPN access permanently | `WireGuard offboard environment` |
| Reallocate peer to new env | Offboard old env → onboard new env |
| Rancher grant timeout / KUBECONFIG missing | Re-run terraform with `GRANT_GROUP_ACCESS=false`; see [agents.md](agents.md) |

See also: [SELF_SERVICE_DEPLOYMENT_GUIDE.md](SELF_SERVICE_DEPLOYMENT_GUIDE.md), [agents.md](agents.md)
