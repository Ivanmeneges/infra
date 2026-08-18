# GitHub Actions configuration

## `rancher-access-grants.json`

Team → Rancher cluster role catalog used by `rancher-grant-cluster-access.sh apply` after infra deploy.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `group` | Yes | IdP group name (Keycloak), e.g. `DEVOPS`, `QA` |
| `role` | Yes | Rancher **cluster role template id** — use built-in ids where possible (`cluster-owner`, `cluster-member`, `read-only`) or custom `rt-xxxxx` ids |
| `enabled` | Yes | `true` to include in default merges; `false` to keep in catalog but skip until enabled via workflow/env |
| `principal_id` | No | Full group principal; default is built from `RANCHER_GROUP_AUTH_PREFIX` or auto-detect |
| `fix_misbound_user` | No | When `true`, repair userPrincipalId bindings that should be group bindings (DEVOPS only by default) |

### Built-in vs custom role template ids

Rancher built-in cluster roles use stable ids:

- `cluster-owner`
- `cluster-member`
- `read-only`

Custom roles created in Rancher UI get ids like `rt-jdzrj`. These are **per Rancher installation**.

### Discover role template ids

```bash
export RANCHER_URL="https://rancher.example.com"
export RANCHER_TOKEN="token-xxxxx:yyyyy"

curl -sS \
  -H "Authorization: Bearer ${RANCHER_TOKEN}" \
  "${RANCHER_URL}/v3/roletemplates?limit=1000" \
  | jq '[.data[] | select(.context == "cluster" or (.links // {}) | has("cluster")) | {id, name, builtin}]'
```

Or: Rancher UI → **Users & Authentication** → **Roles** → **Cluster**.

### Per-environment overrides

Set GitHub **environment variable** `RANCHER_ACCESS_GRANTS` (JSON array patch, merged onto this file):

```json
[
  { "group": "QA", "role": "rt-jdzrj", "enabled": true }
]
```

Other optional environment variables (see `rancher-grant-cluster-access.sh --help`):

- `RANCHER_DEVOPS_ROLE`, `RANCHER_DEVOPS_ENABLED`, `RANCHER_DEVOPS_GROUP`
- `RANCHER_GROUP_AUTH_PREFIX` (e.g. `keycloak_group`)

Workflow inputs `GRANT_GROUP_ACCESS` and `RANCHER_CLUSTER_OWNER_GROUP_*` apply a runtime patch for non-DEVOPS teams.

### Safety defaults

- Only entries with `"enabled": true` are applied.
- Missing `enabled` in patches is treated as **disabled** during merge (explicit enable required).
- DEVOPS `cluster-owner` stays enabled in the catalog regardless of `GRANT_GROUP_ACCESS`.
