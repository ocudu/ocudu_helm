# RU Emulator

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying the srsRAN Radio Unit (O-RU) emulator

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

## Overview

This chart deploys an O-RU (Open Radio Unit) emulator that communicates with DU units via the OpenFronthaul protocol. It simulates a real Radio Unit for testing and development purposes.

> **⚠️ Important**: This chart requires a container image with the `ru_emulator` binary. The standard srsRAN Project image does not include this binary. You must build or obtain a specific RU emulator image before deploying.

**Capabilities**:
- OpenFronthaul protocol support
- DPDK-based high-performance packet processing
- Multiple cell configuration
- VLAN tagging support

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Kubernetes**: >= 1.24.0
2. **Network**: Physical network interface for OpenFronthaul communication
3. **Privileges**: Chart requires `hostNetwork: true` and `privileged: true` for DPDK and NIC access
4. **Node Selection**: Use `nodeSelector` to target nodes with appropriate hardware

## Installing the Chart

**Basic installation**:
```bash
cd charts/ru_emulator
helm install ru-emulator ./
```

**With custom configuration**:
```bash
helm install ru-emulator ./ -f my-values.yaml
```

## Verifying Installation

Check deployment status:
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=ru-emulator

# View logs
kubectl logs -l app.kubernetes.io/name=ru-emulator

# Check network configuration
kubectl exec -it <pod-name> -- ip addr show
```

## Uninstalling the Chart

```bash
helm uninstall ru-emulator
```

The command removes all Kubernetes components associated with the chart.


## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `"srsran/ru-emulator"` | Container image repository |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `network.hostNetwork` | bool | `true` | **REQUIRED**: Enable host network for direct NIC access |
| `securityContext.privileged` | bool | `true` | **REQUIRED**: Enable privileged mode for DPDK |
| `config.ru_emu.cells` | list | See values.yaml | Cell configuration (interfaces, MAC addresses, VLAN) |
| `replicaCount` | int | `32` | Number of emulated RU instances |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### Single Cell Emulator

```yaml
image:
  repository: <your-ru-emulator-image>  # REQUIRED: Custom image with ru_emulator binary
  tag: "latest"

config:
  ru_emu:
    cells:
    - bandwidth: 100
      network_interface: enp1s0f0
      ru_mac_addr: 50:7c:6f:45:44:33
      du_mac_addr: 00:11:22:33:44:00
      vlan_tag: 6

replicaCount: 1

resources:
  limits:
    cpu: 4
    memory: 4Gi
  requests:
    cpu: 4
    memory: 4Gi

nodeSelector:
  kubernetes.io/hostname: worker-node-1
```

### Multi-Cell with Higher Resources

```yaml
replicaCount: 8

resources:
  limits:
    cpu: 8
    memory: 8Gi
  requests:
    cpu: 8
    memory: 8Gi
```

## Architecture & Design

### Why hostNetwork and privileged are Required

**`hostNetwork: true`** is mandatory because:
- Direct access to physical network interfaces
- DPDK requires raw socket access
- OpenFronthaul uses Layer 2 Ethernet frames

**`privileged: true`** is mandatory because:
- DPDK initialization and hugepage access
- Network interface configuration (`SYS_NICE`, `NET_ADMIN` capabilities)
- Hardware timestamping for synchronization

### Deployment Model

- **Deployment**: Stateless replicas for load testing
- **Default replicas**: 32 (configurable)
- **hostNetwork**: Shares host network namespace

## Troubleshooting

### Pod fails with network errors
```bash
# Verify interface exists
kubectl exec -it <pod-name> -- ip link show

# Check interface name in config
kubectl get configmap -o yaml | grep network_interface

# Common issues:
# - Interface name incorrect
# - Interface not present on target node
```

### Binary not found error
```bash
# If you see: "/usr/local/bin/ru_emulator: No such file or directory"
# The container image does not include the ru_emulator binary

# Solution:
# - Build or obtain a custom image with ru_emulator binary
# - Update image.repository in values.yaml
```

### Permission denied errors
```bash
# Verify security context
kubectl describe pod <pod-name> | grep -A10 "Security Context"

# Ensure both are set:
# - network.hostNetwork: true
# - securityContext.privileged: true
```

## Support

- **Documentation**: [srsRAN Project Docs](https://docs.srsran.com)
- **OpenFronthaul**: [O-RAN Alliance Specifications](https://www.o-ran.org/)

## License

AGPL-3.0 - See LICENSE file for details
