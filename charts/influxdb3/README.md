# InfluxDB 3

> **⚠️ PoC/Demo - Not for Production Use**
> 
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

A Helm chart for InfluxDB 3 Core time-series database

This Helm chart deploys a simple, single-node InfluxDB 3 instance in Kubernetes for metrics storage.

## Prerequisites

**For hostPath storage** (default), create the directory on your nodes:

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

**Basic installation** (hostPath storage):
```bash
helm install influxdb3 ./charts/influxdb3
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

The command removes all the Kubernetes components associated with the chart and deletes the release.

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

### Authentication

⚠️ **Default**: Authentication is **disabled** (`--without-auth`) for PoC/Demo.

**For Production**, remove `--without-auth` from `args` and configure authentication:
```yaml
args:
  - --object-store=memory
  - --data-dir=/var/lib/influxdb3
  - --plugin-dir=/var/lib/influxdb3-plugins
  - --node-id=node0
  - --http-bind=0.0.0.0:8081
  # --without-auth removed - configure via env vars or secrets
```

### Data Retention

Configure automatic data deletion with retention policies:
```yaml
args:
  # ... other args ...
  - --retention-period=30d  # 7d, 30d, 90d, 1y
```

### Key Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `image.repository` | `influxdb` | Container image |
| `image.tag` | `3.1.0-core` | Image tag |
| `service.port` | `8081` | HTTP API port |
| `persistence.type` | `hostPath` | Storage type (pvc or hostPath) |
| `persistence.pvc.size` | `50Gi` | PVC data size |
| `persistence.hostPath.path` | `/mnt/influxdb3` | Host path |

See [values.yaml](values.yaml) for complete configuration options.

## Troubleshooting

**Permissions Issues**: Ensure directories are owned by UID/GID 1000 or set `podSecurityContext.fsGroup: 1000`.

**PVC Not Binding**: Check StorageClass availability with `kubectl get storageclass`.

For more information, see [InfluxDB 3 Documentation](https://docs.influxdata.com/influxdb/v3/).
