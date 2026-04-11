# PostgreSQL Replication in Kubernetes

Bumping `replicas: 3` on a vanilla postgres StatefulSet gives three **independent** databases that don't know about each other — not replication.

## Option 1: Operator (recommended)

### CloudNativePG

Most mature option. Single CRD handles streaming replication, failover, and backups.

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-postgres
  namespace: pg
spec:
  instances: 3
  storage:
    size: 2Gi
    storageClass: hostpath
```

Install: https://cloudnative-pg.io/

### Alternatives

- **Zalando Postgres Operator** — good multi-team/multi-DB support
- **CrunchyData PGO** — strong backup/restore story

## Option 2: DIY streaming replication

Requires init containers, `pg_basebackup`, separate ConfigMaps for primary vs replica, and a sidecar or script for failover. Doable but brittle glue for a solved problem.

## Recommendation

- **Local dev**: single replica is fine, don't add complexity you don't need.
- **HA required**: install CloudNativePG and replace `db-postgresql.yaml` entirely.
