# ocudu-cu-cp

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)

A Helm chart for deploying the OCUDU 5G CU-CP (Central Unit - Control Plane)

## Overview

CU-CP terminates N2 (NGAP, toward the AMF), E1AP (toward CU-UP), and F1-C (F1AP, toward the DU). It was split out from the combined `ocudu-cu` chart.

## Installing the Chart

```bash
helm install ocudu-cu-cp oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-cp --version 1.1.0
```

**Local installation**:
```bash
cd charts/ocudu-cu-cp
helm install ocudu-cu-cp ./ -f my-values.yaml
```

## Verifying Installation

```bash
# Check pod status
kubectl get pod -l app.kubernetes.io/name=ocudu-cu-cp

# View logs
kubectl logs -l app.kubernetes.io/name=ocudu-cu-cp -f
```

A successful start logs `N2: Connection to AMF on <addr>:38412 completed`
and `==== CU-CP started ===`.

## Uninstalling the Chart

```bash
helm uninstall ocudu-cu-cp
```

This removes all Kubernetes resources associated with the chart.

## Upgrading

```bash
helm upgrade ocudu-cu-cp oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-cp --version 1.1.0 -f my-values.yaml
```

The chart sets `deploymentStrategy.type: Recreate` by default — the old pod
is fully terminated before the new one starts, since this is a stateful
workload that should not run overlapping old/new pods.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `network.hostNetwork` | bool | `false` | Enable host network mode |
| `n2Service.enabled` | bool | `true` | Enable N2 (NGAP) Service |
| `e1Service.enabled` | bool | `false` | Enable E1 (E1AP) Service |
| `f1cService.enabled` | bool | `true` | Enable F1-C (F1AP) Service |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only effective when `hostNetwork: false`) |
| `metricsService.enabled` | bool | `false` | Enable the metrics/remote-control WebSocket endpoint |
| `metricsService.powercap.enabled` | bool | `false` | No effect on capabilities — `PERFMON` is always granted |
| `persistence.enabled` | bool | `true` | Enable persistent storage for logs |
| `persistence.type` | string | `"hostPath"` | Storage type: `pvc` or `hostPath` |
| `rbac.create` | bool | `true` | Create RBAC Role and RoleBinding |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `deploymentStrategy.type` | string | `"Recreate"` | Deployment update strategy |
| `config.cu-cp-config.yml` | string | See `values.yaml` | CU-CP application configuration file |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### CNI + ClusterIP with E1/F1 enabled

```yaml
network:
  hostNetwork: false

e1Service:
  enabled: true
f1cService:
  enabled: true

config:
  cu-cp-config.yml: |-
    cu_cp:
      amf:
        addrs: open5gs-sample-amf-ngap.default
        bind_addrs: 0.0.0.0
      e1ap:
        bind_addrs: 0.0.0.0
      f1ap:
        bind_addrs: 0.0.0.0
```

### hostPath persistence with log rotation

```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/debugging-logs"
    type: DirectoryOrCreate
  preserveOldLogs: true
```

The target directory must exist and be owned by uid 1000 on the node before
deploying — `fsGroup` does not apply to hostPath volumes.

## Support

- **Documentation**: [OCUDU Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Issues**: [GitLab Issues](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/issues)

## License

BSD-3-Clause-Open-MPI - See LICENSE file for details
