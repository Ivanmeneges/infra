# GitHub automation config

## `rancher-access-grants.json`

Default Rancher cluster RBAC grants applied after `ENABLE_RANCHER_IMPORT=true` in Terraform.

Each object:

| Field | Required | Example |
|-------|----------|---------|
| `group` | yes | `DEVOPS` |
| `role` | yes | `cluster-owner`, `cluster-member` |
| `principal_id` | no | `keycloak_group://DEVOPS` |
| `group_auth_prefix` | no | `keycloak_group` (used if `principal_id` omitted) |
| `fix_misbound_user` | no | `true` — repair wrong DEVOPS bindings |

### Multiple teams example

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

### Per-environment override (no workflow input changes)

Set GitHub **environment variable** `RANCHER_ACCESS_GRANTS` to a JSON array (same schema).  
The Terraform workflow uses `vars.RANCHER_ACCESS_GRANTS` when set; otherwise it reads this file.

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
