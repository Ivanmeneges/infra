# GitHub automation config

## `rancher-access-grants.json`

**Repo-wide defaults** for Rancher cluster RBAC after `ENABLE_RANCHER_IMPORT=true`.

Layers are **merged by `group` name** (later layers win):

| Layer | Source | Purpose |
|-------|--------|---------|
| 1. Base | `.github/config/rancher-access-grants.json` | Team catalog + default roles |
| 2. Env patch | `vars.RANCHER_ACCESS_GRANTS` | Per-environment defaults |
| 3. DEVOPS shortcuts | `vars.RANCHER_DEVOPS_ROLE`, `vars.RANCHER_DEVOPS_ENABLED` | Per-env DEVOPS override |
| 4. **Workflow UI** | `terraform.yml` inputs (see below) | **Per-run selections — highest priority** |

### Workflow inputs (when you click Run workflow)

| Input | Default | What it does |
|-------|---------|--------------|
| `GRANT_RANCHER_ACCESS` | ✅ true | Master switch |
| `RANCHER_GRANT_DEVOPS` | ✅ true | Grant DEVOPS |
| `RANCHER_DEVOPS_GROUP` | `DEVOPS` | DEVOPS group name (Keycloak/Rancher) |
| `RANCHER_DEVOPS_ROLE` | `cluster-owner` | DEVOPS role this run |
| `RANCHER_GRANT_GROUPS` | (empty) | Comma-separated teams from JSON to enable, e.g. `QA,DEVELOPERS` — **roles come from JSON** |
| `RANCHER_CLUSTER_OWNER_GROUPS` | (empty) | Comma-separated groups for **cluster-owner**, e.g. `QA` or `DEVOPS,QA` |

**Add a new team:** edit `rancher-access-grants.json` only — no workflow YAML change. Then select it in `RANCHER_GRANT_GROUPS` when you run Terraform.

**Example:** DEVOPS owner (default) + QA owner for one run:
- `RANCHER_GRANT_GROUPS` = `QA`
- `RANCHER_CLUSTER_OWNER_GROUPS` = `QA`

**Example:** DEVOPS owner + QA member:
- `RANCHER_GRANT_GROUPS` = `QA`
- leave `RANCHER_CLUSTER_OWNER_GROUPS` empty (uses `cluster-member` from JSON)

**Example:** QA owns the cluster (DEVOPS still member):
- `RANCHER_DEVOPS_ROLE` = `cluster-member`
- `RANCHER_GRANT_GROUPS` = `QA`
- `RANCHER_CLUSTER_OWNER_GROUPS` = `QA`

### Grant entry fields

| Field | Required | Default | Example |
|-------|----------|---------|---------|
| `group` | yes | — | `DEVOPS` |
| `role` | yes | — | `cluster-owner`, `cluster-member` |
| `enabled` | no | `true` | `false` skips this group for that layer |
| `principal_id` | no | built from prefix | `keycloak_group://DEVOPS` |
| `group_auth_prefix` | no | `keycloak_group` | |
| `fix_misbound_user` | no | `false` | `true` for DEVOPS repair |

### Default file (DEVOPS owner; others off)

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

### Per-environment: enable QA only

**Environment `qajava11` → Variable `RANCHER_ACCESS_GRANTS`:**

```json
[
  { "group": "QA", "enabled": true }
]
```

**Result for `qajava11`:** DEVOPS `cluster-owner` + QA `cluster-member`.

### Per-environment: change DEVOPS role (override base)

**Option A — patch variable:**

```json
[{ "group": "DEVOPS", "role": "cluster-member" }]
```

**Option B — shortcut variable (simpler):**

| Variable | Value |
|----------|-------|
| `RANCHER_DEVOPS_ROLE` | `cluster-member` |

DEVOPS keeps `principal_id` / `fix_misbound_user` from base file; only `role` changes.

### Per-environment: disable DEVOPS grant entirely

| Variable | Value |
|----------|-------|
| `RANCHER_DEVOPS_ENABLED` | `false` |

### Merge rules

- Matching `group` → override fields **replace** base fields (shallow merge).
- `enabled: false` → group is **not** granted (skipped).
- New group in env patch only → added to the plan.
- Omitted `enabled` → treated as `true`.

---

## `environment-protection.json`

Default required reviewers for the **Setup environment protection** workflow.

| Field | Description |
|-------|-------------|
| `reviewer_teams` | GitHub org team **slugs**, e.g. `["devops"]` |
| `reviewer_users` | GitHub usernames, e.g. `["alice"]` |
| `deployment_branches` | Branches allowed to deploy to the environment (empty = all) |
| `prevent_self_review` | `true` blocks the workflow starter from approving their own run |
| `wait_timer_minutes` | Optional delay before reviewers can approve |

After running **Setup environment protection** for `qajava11`, any job with `environment: qajava11` pauses until a reviewer approves.
