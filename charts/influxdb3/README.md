# InfluxDB 3

A Helm chart for InfluxDB 3 Core time-series database

This Helm chart deploys a single-node InfluxDB 3 instance in Kubernetes for
metrics storage. The defaults are the demo configuration: authorization off,
in-memory object store, and hostPath persistence. Authorization, TLS, a
file-backed object store on a PVC, and a retention period are all supported but
**opt-in** — see [Authentication and TLS](#authentication-and-tls) and
[Data Retention](#data-retention) — because enabling them requires credentials
and certificates that remain the administrator's responsibility.

## Prerequisites

**For hostPath storage**, create the directories on your nodes and give them to
the user the server runs as:

```bash
sudo mkdir -p /mnt/influxdb3 /mnt/influxdb3-plugins
sudo chown -R 1500:1500 /mnt/influxdb3*
sudo chmod -R 0775 /mnt/influxdb3*
```

`1500` is the `influxdb3` uid/gid inside the upstream image. Two things make this
a hard requirement rather than a nicety:

- The default `args` pass `--plugin-dir`, which enables the Processing Engine.
  The server **creates a Python virtualenv inside that directory on first
  start** (roughly 13 MB); it is not part of the image. If the directory is not
  writable, the server panics during startup with
  `VenvError(InitError("Activation script not found at .../.venv/bin/activate"))`
  and crash-loops. Remove `--plugin-dir` from `args` if you do not use plugins.
- `fsGroup` does **not** apply to hostPath volumes — kubelet only manages
  ownership for volume types that support it. A `podSecurityContext` alone
  therefore cannot fix the permissions; the directories must already be owned
  correctly on the node. kubelet creates a missing `DirectoryOrCreate` hostPath
  as `root:root 0755`, which is not writable by uid 1500.

PVC persistence (`persistence.type: pvc`) has no such prerequisite when the
provisioner creates group- or world-writable volume directories, as the
`local-path` provisioner does.

## Installing the Chart

The chart installs with no prerequisites beyond the storage above. Everything in
this section from the Secret onwards applies only when you opt in to
authorization.

Create a Secret containing a preconfigured admin-token JSON document:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: influxdb3-auth
type: Opaque
stringData:
  token: apiv3_replace_with_a_real_token
  admin-token.json: |
    {"token":"apiv3_replace_with_a_real_token","name":"_admin"}
```

The file is used only to initialize an empty data directory. The raw `token`
key is for clients; use an external Secret manager in production.

**Basic installation**:

**From OCI registry**:
```bash
helm install influxdb3 oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/influxdb3 --version 2.0.0
```

**From local chart**:
```bash
helm install influxdb3 ./charts/influxdb3 \
  --set auth.adminToken.existingSecret=influxdb3-auth
```

**With PVC storage**:
```bash
helm install influxdb3 ./charts/influxdb3 \
  --set persistence.type=pvc \
  --set persistence.pvc.storageClassName=standard \
  --set persistence.pvc.size=50Gi
```

**PVC example with values file**:
```yaml
# influxdb3-values.yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    # Use your cluster's StorageClass
    storageClassName: "openebs-hostpath"  # or "standard", "gp2", etc.
    accessMode: ReadWriteOnce
    size: 50Gi
    pluginsSize: 1Gi
    annotations:
      helm.sh/resource-policy: keep

auth:
  enabled: true
  adminToken:
    existingSecret: influxdb3-auth

podSecurityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

```bash
helm install influxdb3 ./charts/influxdb3 -f influxdb3-values.yaml
```

## Uninstalling the Chart

To uninstall/delete the influxdb3 deployment:

```console
helm delete influxdb3
```

The command removes the workload and release, and with it the PVCs. To keep the
data across an uninstall, set the retain annotation before installing:

```yaml
persistence:
  pvc:
    annotations:
      helm.sh/resource-policy: keep
```

Retained claims survive `helm delete` and are reused by a reinstall of the same
release name. Delete them explicitly only when their data is no longer needed:

```console
kubectl delete pvc <release>-influxdb3-data <release>-influxdb3-plugins
```

## Configuration

### Storage

Two storage modes are supported:

**PVC (Cloud/Dynamic Provisioning)**:
```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: "standard"
    size: 50Gi
    pluginsSize: 1Gi
```

**hostPath (Bare-Metal)**:
```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: /mnt/influxdb3
    pathType: DirectoryOrCreate
```

### Authentication and TLS

Authorization is disabled by default. Enable it and supply a preconfigured admin
token to bootstrap an empty database:

```yaml
auth:
  enabled: true
  adminToken:
    existingSecret: influxdb3-auth
    key: admin-token.json
tls:
  enabled: true
  existingSecret: influxdb3-tls
  minimumVersion: tls-1.2
```

The TLS Secret must contain `tls.crt`, `tls.key`, and `ca.crt`. The CA is also
mounted so authenticated administrative CLI operations can verify the server.
Leaving `auth.enabled=false` is intended only for disposable development
environments; it renders `--without-auth`, so the API is unauthenticated.

Setting `auth.enabled=true` without `auth.adminToken.existingSecret` is a
misconfiguration: neither `--without-auth` nor `--admin-token-file` is passed and
the server comes up with no usable credential. Always set both together.

### Data Retention

InfluxDB 3 Core accepts a retention period **only when a database is created**
and cannot change it afterwards. The chart therefore applies retention through a
post-install hook Job that creates the database for you, which requires a
database name and the admin token:

```yaml
database: ocudu
retentionPeriod: 30d
auth:
  enabled: true
  adminToken:
    existingSecret: influxdb3-auth
```

All four settings are required; with any of them unset the hook does not render
and no retention is applied. Applying retention to a database that already exists
means recreating it, which discards its data.

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `influxdb` | Container image |
| `image.tag` | `3.1.0-core` | Image tag |
| `service.port` | `8081` | HTTP API port |
| `persistence.type` | `hostPath` | Storage type (pvc or hostPath) |
| `persistence.pvc.size` | `50Gi` | PVC data size |
| `persistence.hostPath.path` | `/mnt/influxdb3` | Host path |
| `auth.enabled` | `false` | Require API authorization |
| `auth.adminToken.existingSecret` | `""` | Bootstrap-token Secret, required when `auth.enabled` |
| `tls.enabled` | `false` | Serve the API over TLS |
| `database` | `""` | Database created by the retention hook |
| `retentionPeriod` | `""` | Retention applied when that database is created |

See [values.yaml](values.yaml) for complete configuration options.

## Troubleshooting

**Permissions Issues**: Ensure the storage directories are owned by UID/GID
**1500**, the `influxdb3` user in the image. For PVCs, `podSecurityContext.fsGroup: 1500`
works; for hostPath it does not, because kubelet does not manage ownership of
hostPath volumes — fix the ownership on the node instead.

**Crash loop with `VenvError` / `Activation script not found at
"/var/lib/influxdb3-plugins/.venv/bin/activate"`**: the Processing Engine
(enabled by `--plugin-dir` in the default `args`) creates a Python virtualenv in
the plugin directory on first start and cannot write there. Either make the
plugin volume writable by uid 1500 — see [Prerequisites](#prerequisites) — or
remove `--plugin-dir` from `args` if you do not use plugins.

**PVC Not Binding**: Check StorageClass availability with `kubectl get storageclass`.

For more information, see [InfluxDB 3 Documentation](https://docs.influxdata.com/influxdb/v3/).
