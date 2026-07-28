# InfluxDB 3

A Helm chart for InfluxDB 3 Core time-series database

This Helm chart deploys a single-node InfluxDB 3 instance in Kubernetes for
metrics storage. Authentication and file-backed PVC persistence are enabled by
default. TLS is optional because certificate issuance remains the
administrator's responsibility.

## Prerequisites

**For hostPath storage**, create the directory on your nodes:

```bash
sudo mkdir -p /mnt/influxdb3 /mnt/influxdb3-plugins
sudo chown -R 1000:1000 /mnt/influxdb3*
sudo chmod -R 0775 /mnt/influxdb3*
```

Configure security context to write to these directories:
```yaml
podSecurityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

## Installing the Chart

Create a Secret containing a preconfigured admin-token JSON document:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: influxdb3-auth
type: Opaque
stringData:
  admin-token.json: |
    {"token":"apiv3_replace_with_a_real_token"}
```

The file is used only to initialize an empty data directory. Keep the raw
token separately for clients and use an external Secret manager in production.

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

The command removes the workload and release. PVCs carry
`helm.sh/resource-policy: keep` by default and therefore remain. Delete them
explicitly only when their data is no longer needed:

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

Authentication is enabled by default. Supply a preconfigured admin token to
bootstrap an empty database:

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

The TLS Secret must contain `tls.crt` and `tls.key`. Disabling authentication
with `auth.enabled=false` is intended only for disposable development
environments.

### Data Retention

Configure automatic data deletion with retention policies:
```yaml
retentionPeriod: 30d
```

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `influxdb` | Container image |
| `image.tag` | `3.1.0-core` | Image tag |
| `service.port` | `8081` | HTTP API port |
| `persistence.type` | `pvc` | Storage type (pvc or hostPath) |
| `persistence.pvc.size` | `50Gi` | PVC data size |
| `persistence.hostPath.path` | `/mnt/influxdb3` | Host path |
| `auth.enabled` | `true` | Require API authorization |
| `auth.adminToken.existingSecret` | `""` | Optional bootstrap-token Secret |
| `tls.enabled` | `false` | Serve the API over TLS |
| `retentionPeriod` | `30d` | Default data retention |

See [values.yaml](values.yaml) for complete configuration options.

## Troubleshooting

**Permissions Issues**: Ensure directories are owned by UID/GID 1000 or set `podSecurityContext.fsGroup: 1000`.

**PVC Not Binding**: Check StorageClass availability with `kubectl get storageclass`.

For more information, see [InfluxDB 3 Documentation](https://docs.influxdata.com/influxdb/v3/).
