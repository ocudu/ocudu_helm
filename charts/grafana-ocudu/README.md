# Grafana Monitoring Stack

> **⚠️ PoC/Demo - Not for Production Use**
> 
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

## Overview

A Helm chart for deploying a complete monitoring stack for OCUDU metrics visualization.

**Stack Components**:
- **Grafana** (v9.2.10): Visualization and dashboards
- **InfluxDB 3 Core** (v3.1.0): Time-series database
- **Telegraf** (v1.8.60): Metrics collection agent

**Custom Features**:
- Pre-configured OCUDU dashboards
- Real-time metrics collection (1s interval)
- Optimized for 5G RAN KPIs

## Prerequisites

Before installing:

1. **Dependencies**: Chart requires internet access to pull upstream Helm charts
   ```bash
   helm dependency build charts/grafana-ocudu/
   ```

2. **Storage**: If using persistent storage for InfluxDB3
   ```bash
   # Create directory on target node
   sudo mkdir -p /mnt/influxdb3
   sudo chown -R 1000:1000 /mnt/influxdb3
   ```

3. **Metrics Source**: Configure Telegraf to point to your OCUDU metrics endpoint

## Installing the Chart

**Build dependencies first**:
```bash
cd charts/grafana-ocudu
helm dependency build
```


**From OCI registry**:
```bash
helm install grafana-ocudu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/grafana-ocudu --version 2.0.0 \
  --namespace ocudu --create-namespace
```

**From local chart**:
**Basic installation**:
```bash
helm install grafana ./ --namespace ocudu --create-namespace
```

**With custom values**:
```bash
helm install grafana ./ -n ocudu -f my-values.yaml
```

**Access Grafana**:
```bash
# If using NodePort (default)
kubectl get svc -n ocudu grafana

# Forward port for local access
kubectl port-forward -n ocudu svc/grafana 3000:80
# Then access: http://localhost:3000
# Default credentials: admin / admin1234
```

## Uninstalling the Chart

To uninstall/delete the grafana deployment:

```console
helm delete grafana
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Component Versions

This chart uses pinned versions for reproducible deployments:

| Component | Version | Upstream Chart | Purpose |
|-----------|---------|----------------|---------|
| Grafana | 9.2.10 | grafana/grafana | Visualization |
| Telegraf | 1.8.60 | influxdata/telegraf | Metrics collection |
| InfluxDB3 | 1.0.0 | ocudu/influxdb3 | Time-series storage |

> **Note**: These versions are tested together. Upgrading requires testing the full stack.

## Configuration

### Key Configuration Examples

**Custom Admin Credentials** (REQUIRED for any deployment):
```yaml
grafana:
  env:
    GF_SECURITY_ADMIN_USER: "myadmin"
    GF_SECURITY_ADMIN_PASSWORD: "MySecurePassword123!"
```

**Custom Metrics Endpoint**:
```yaml
telegraf:
  env:
    - name: WS_URL
      value: "my-gnb-metrics.namespace:8001"
```

**Persistent Storage for InfluxDB3**:
```yaml
influxdb3:
  persistence:
    enabled: true
    size: 100Gi  # Increase for longer retention
    hostPath: /mnt/influxdb3  # Or use PVC
```

**Disable Anonymous Access** (recommended):
```yaml
grafana:
  env:
    GF_AUTH_ANONYMOUS_ENABLED: "false"
```

### Chart Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| grafana.image.repository | string | `"softwareradiosystems/grafana"` | Grafana image repository |
| grafana.image.tag | string | `"11c9bbabb6__2025-09-15"` | Grafana image tag |
| grafana.env.GF_VERSION | string | `"12.0.2"` | Grafana version |
| grafana.env.GF_PORT | string | `"3000"` | Grafana port |
| grafana.env.GF_AUTH_ANONYMOUS_ENABLED | string | `"true"` | Enable anonymous access |
| grafana.env.GF_AUTH_ANONYMOUS_ORG_ROLE | string | `"Viewer"` | Anonymous user role |
| grafana.env.GF_SECURITY_ADMIN_USER | string | `"admin"` | Admin username |
| grafana.env.GF_SECURITY_ADMIN_PASSWORD | string | `"admin1234"` | Admin password |
| grafana.env.INFLUXDB3_EXTERNAL_URL | string | `"http://influxdb3.ocudu:8081"` | InfluxDB 3 external URL |
| grafana.env.INFLUXDB3_AUTH_TOKEN | string | `"fake-token-1234567890abcdef"` | InfluxDB 3 auth token |
| grafana.env.INFLUXDB3_BUCKET | string | `"ocudu"` | InfluxDB 3 bucket name |
| grafana.service.enabled | bool | `true` | Enable Grafana service |
| grafana.service.type | string | `"NodePort"` | Service type |
| grafana.service.port | int | `80` | Service port |
| grafana.service.targetPort | int | `3000` | Target port |
| grafana.service.nodePort | int | `30001` | Node port |
| influxdb3.image.repository | string | `"influxdb"` | InfluxDB 3 image repository |
| influxdb3.image.tag | string | `"3.1.0-core"` | InfluxDB 3 image tag |
| influxdb3.service.type | string | `"ClusterIP"` | InfluxDB 3 service type |
| influxdb3.service.port | int | `8081` | InfluxDB 3 service port |
| influxdb3.persistence.enabled | bool | `true` | Enable InfluxDB 3 persistence |
| influxdb3.persistence.type | string | `"hostPath"` | Persistence type |
| influxdb3.persistence.hostPath | string | `"/mnt/influxdb3"` | Host path for data storage |
| influxdb3.persistence.accessMode | string | `"ReadWriteOnce"` | Access mode |
| influxdb3.persistence.size | string | `"50Gi"` | Storage size |
| influxdb3.persistence.mountPath | string | `"/var/lib/influxdb3"` | Data mount path |
| influxdb3.persistence.pluginMountPath | string | `"/var/lib/influxdb3-plugins"` | Plugin mount path |
| telegraf.useImageConfig | bool | `true` | Use image config for Telegraf |
| telegraf.image.repo | string | `"softwareradiosystems/telegraf"` | Telegraf image repository |
| telegraf.image.tag | string | `"11c9bbabb6__2025-09-15"` | Telegraf image tag |
| telegraf.env.WS_URL | string | `"ocudu-gnb-metrics.ocudu:8001"` | WebSocket URL |
| telegraf.env.INFLUXDB3_EXTERNAL_URL | string | `"http://influxdb3.ocudu:8081"` | InfluxDB 3 URL for Telegraf |
| telegraf.env.INFLUXDB3_AUTH_TOKEN | string | `"fake-token-1234567890abcdef"` | InfluxDB 3 auth token for Telegraf |
| telegraf.env.INFLUXDB3_BUCKET | string | `"ocudu"` | InfluxDB 3 bucket for Telegraf |
| telegraf.env.TELEGRAF_INPUT_INTERVAL | string | `"1s"` | Input interval |
| telegraf.env.TELEGRAF_OUTPUT_INTERVAL | string | `"1s"` | Output interval |
| telegraf.env.TELEGRAF_BUFFER_LIMIT | string | `"10000"` | Buffer limit |
| telegraf.service.enabled | bool | `false` | Enable Telegraf service |

For complete parameter documentation, see the upstream chart documentation:
- [Grafana Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/grafana)
- [Telegraf Helm Chart](https://github.com/influxdata/helm-charts/tree/master/charts/telegraf)
- [InfluxDB3 Helm Chart](../influxdb3)

## Custom Dashboards

The Grafana image includes pre-configured OCUDU dashboards:
- **Home Dashboard**: Overview of gNB metrics
- **OCUDU Metrics**: Detailed 5G RAN KPIs

**Dashboards included in custom image**:
```
grafana.image.repository: softwareradiosystems/grafana
grafana.image.tag: "11c9bbabb6__2025-09-15"
```

**To add custom dashboards**:
1. Build custom Grafana image with your dashboards in `/etc/dashboards/`
2. Update `grafana.image.repository` and `grafana.image.tag`
3. Configure dashboard path in `grafana.env.GF_DASHBOARDS_DEFAULT_HOME_DASHBOARD_PATH`

## Troubleshooting

### Grafana not accessible
```bash
# Check service
kubectl get svc -n ocudu grafana

# Check pods
kubectl get pods -n ocudu -l app.kubernetes.io/name=grafana

# Check logs
kubectl logs -n ocudu -l app.kubernetes.io/name=grafana
```

### No metrics in Grafana
```bash
# 1. Check Telegraf is collecting
kubectl logs -n ocudu -l app.kubernetes.io/name=telegraf | grep "error\|warn"

# 2. Verify metrics endpoint is reachable
kubectl exec -n ocudu -it deployment/grafana-telegraf -- curl http://WS_URL

# 3. Check InfluxDB3 is receiving data
kubectl logs -n ocudu -l app.kubernetes.io/name=influxdb3
```

### Dependencies not found
```bash
# Rebuild dependencies
cd charts/grafana-ocudu
helm dependency build

# Check charts/ directory was created
ls -la charts/
```

## Architecture

```
┌─────────────┐      metrics        ┌──────────────┐
│  OCUDU gNB  │ ──────────────────> │  Telegraf    │
│  (metrics)  │  :8001 websocket    │ (collector)  │
└─────────────┘                     └──────┬───────┘
                                           │ write
                                           v
                                    ┌──────────────┐
                                    │  InfluxDB3   │
                                    │  (storage)   │
                                    └──────┬───────┘
                                           │ query
                                           v
                                    ┌──────────────┐
                                    │   Grafana    │
                                    │ (visualize)  │
                                    └──────────────┘
```

## Support

- **Grafana Docs**: [grafana.com/docs](https://grafana.com/docs/)
- **InfluxDB Docs**: [docs.influxdata.com](https://docs.influxdata.com/)
- **Telegraf Docs**: [docs.influxdata.com](https://docs.influxdata.com/telegraf/v1/)

## License

BSD 3-Clause Open MPI variant - See LICENSE file for details
