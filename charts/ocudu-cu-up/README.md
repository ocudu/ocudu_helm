# ocudu-cu-up

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)

A Helm chart for deploying the OCUDU 5G CU-UP (Central Unit - User Plane)

## Overview

CU-UP terminates N3 (GTP-U, toward the UPF), E1AP (toward CU-CP), and F1-U (GTP-U, toward the DU). It was split out from the combined `ocudu-cu` chart.

## Installing the Chart

```bash
helm install ocudu-cu-up oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-up --version 1.1.0
```

**Local installation**:
```bash
cd charts/ocudu-cu-up
helm install ocudu-cu-up ./ -f my-values.yaml
```

## Verifying Installation

```bash
# Check pod status
kubectl get pod -l app.kubernetes.io/name=ocudu-cu-up

# View logs
kubectl logs -l app.kubernetes.io/name=ocudu-cu-up -f
```

A successful start logs `E1: Connection to CU-CP completed` and
`==== CU-UP started ===`.

## Uninstalling the Chart

```bash
helm uninstall ocudu-cu-up
```

This removes all Kubernetes resources associated with the chart.

## Upgrading

```bash
helm upgrade ocudu-cu-up oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-up --version 1.1.0 -f my-values.yaml
```

The chart sets `deploymentStrategy.type: Recreate` by default — the old pod
is fully terminated before the new one starts, since this is a stateful
workload that should not run overlapping old/new pods.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `network.hostNetwork` | bool | `false` | Enable host network mode |
| `n3Service.enabled` | bool | `true` | Enable N3 (GTP-U) Service |
| `e1Service.enabled` | bool | `false` | Enable E1 (E1AP) Service |
| `f1uService.enabled` | bool | `true` | Enable F1-U (GTP-U) Service |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only effective when `hostNetwork: false`) |
| `metricsService.enabled` | bool | `false` | Enable the metrics/remote-control WebSocket endpoint |
| `metricsService.powercap.enabled` | bool | `false` | No effect on capabilities — `PERFMON` is always granted |
| `persistence.enabled` | bool | `true` | Enable persistent storage for logs |
| `persistence.type` | string | `"hostPath"` | Storage type: `pvc` or `hostPath` |
| `rbac.create` | bool | `true` | Create RBAC Role and RoleBinding |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `deploymentStrategy.type` | string | `"Recreate"` | Deployment update strategy |
| `config.cu-up-config.yml` | string | See `values.yaml` | CU-UP application configuration file |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### CNI + ClusterIP with E1/F1-U enabled

```yaml
network:
  hostNetwork: false

e1Service:
  enabled: true
f1uService:
  enabled: true

config:
  cu-up-config.yml: |-
    cu_up:
      e1ap:
        addrs: ocudu-cu-cp-e1
        bind_addrs: 0.0.0.0
      ngu:
        socket:
          - bind_addr: 0.0.0.0
      f1u:
        socket:
          - bind_addr: 0.0.0.0
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
