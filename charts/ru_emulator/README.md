# RU Emulator

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying the OCUDU Radio Unit (O-RU) emulator

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

## Overview

This chart deploys an O-RU (Open Radio Unit) emulator that communicates with DU units via the OpenFronthaul protocol. It simulates a real Radio Unit for testing and development purposes.

> **⚠️ Important**: This chart requires a container image with the `ru_emulator` binary. The standard OCUDU Project image does not include this binary. You must build or obtain a specific RU emulator image before deploying.
>
> **ℹ️ SR-IOV Status**: SR-IOV support is fully implemented with automatic BDF/MAC detection via the entrypoint script. However, it remains **untested end-to-end** due to the missing `ru_emulator` binary in standard images. The SR-IOV resource allocation and configuration replacement logic have been verified in live cluster testing.

**Capabilities**:
- OpenFronthaul protocol support
- DPDK-based high-performance packet processing
- Multiple cell configuration
- VLAN tagging support

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Container Image**: A container image with the `/usr/local/bin/ru_emulator` binary is required
   - The default OCUDU Project image does **not** include this binary
   - You must specify a custom image in `values.yaml`
2. **Kubernetes**: >= 1.24.0
3. **Network Configuration** (choose oneM - See ):
   - **hostNetwork mode**: Physical network interface for OpenFronthaul communication
   - **SR-IOV mode** (recommended for production): SR-IOV device plugin deployed in cluster
4. **Privileges**:
   - **hostNetwork mode**: Requires `hostNetwork: true` and `privileged: true`
   - **SR-IOV mode**: Reduced privileges with specific capabilities (no full privileged mode)
5. **Node Selection**: Use `nodeSelector` to target nodes with appropriate hardware
   - For SR-IOV: Nodes must have SR-IOV-capable NICs with VFs configured

## Installing the Chart

**Basic installation**:

**From OCI registry**:
```bash
helm install ru-emulator oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ru-emulator --version 2.0.0
```

**From local chart**:
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
| `image.repository` | string | `"softwareradiosystems/srsran-project"` | Container image repository |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `network.hostNetwork` | bool | `true` | Enable host network (required when SR-IOV disabled) |
| `securityContext.privileged` | bool | `true` | Enable privileged mode (required for DPDK with hostNetwork) |
| `sriovConfig.enabled` | bool | `false` | Enable SR-IOV device plugin integration |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_netdevice"` | SR-IOV resource name from device plugin |
| `sriovConfig.vfCount` | int | `1` | Number of SR-IOV VFs to request |
| `config.ru_emu.cells` | list | See values.yaml | Cell configuration (interfaces, MAC addresses, VLAN) |
| `replicaCount` | int | `1` | Number of emulated RU instances |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### hostNetwork Mode (Testing/Development)

```yaml
image:
  repository: <your-ru-emulator-image>  # REQUIRED: Custom image with ru_emulator binary
  tag: "latest"

network:
  hostNetwork: true

sriovConfig:
  enabled: false

config:
  ru_emu:
    cells:
    - bandwidth: 100
      network_interface: enp1s0f0  # Physical interface name
      ru_mac_addr: 50:7c:6f:45:44:33
      du_mac_addr: 00:11:22:33:44:00
      vlan_tag: 6

replicaCount: 1

securityContext:
  privileged: true
  capabilities:
    add: ["SYS_NICE", "NET_ADMIN"]

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

### SR-IOV Mode (Production)

```yaml
image:
  repository: <your-ru-emulator-image>
  tag: "latest"

network:
  hostNetwork: false  # Disable for SR-IOV

sriovConfig:
  enabled: true
  extendedResourceName: "intel.com/intel_sriov_netdevice"
  vfCount: 1

config:
  ru_emu:
    cells:
    - bandwidth: 100
      network_interface: ""  # Auto-detected from SR-IOV VF PCI address
      ru_mac_addr: ""   # Auto-detected from dmesg
      du_mac_addr: 50:7c:6f:45:44:33
      vlan_tag: 6

replicaCount: 1

# Reduced privileges with SR-IOV
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    add:
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RAWIO
      - NET_RAW
      - SYS_NICE
  privileged: false

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

### Multi-Cell Load Testing

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

### Network Modes

The RU emulator supports two deployment modes:

**1. hostNetwork Mode (Testing/Development)**
- `network.hostNetwork: true`
- `sriovConfig.enabled: false`
- Direct access to physical network interfaces
- Requires `privileged: true`
- Simpler setup, suitable for testing

**2. SR-IOV Mode (Production)**
- `network.hostNetwork: false`
- `sriovConfig.enabled: true`
- Uses SR-IOV Virtual Functions (VFs)
- Reduced privileges (no privileged mode needed)
- Better isolation and security
- Requires SR-IOV device plugin in cluster

### How SR-IOV Auto-Detection Works

When SR-IOV is enabled, the entrypoint script automatically:

1. **Detects VF PCI Address**: Reads from environment variable set by SR-IOV device plugin
   - Example: `PCIDEVICE_INTEL_COM_INTEL_SRIOV_NETDEVICE=0000:01:10.0`
2. **Extracts MAC Address**: Queries `dmesg` for the VF's MAC address
3. **Updates Configuration**: Replaces `network_interface` and `ru_mac_addr` in config file
4. **Launches Emulator**: Starts with auto-configured network settings

This eliminates manual configuration of PCI addresses and MAC addresses.

### Why Privileges are Required

**hostNetwork Mode**: `privileged: true` because:
- DPDK initialization and hugepage access
- Network interface configuration (`SYS_NICE`, `NET_ADMIN` capabilities)
- Direct hardware access for OpenFronthaul

**SR-IOV Mode**: Reduced privileges (`privileged: false`) with specific capabilities:
- `IPC_LOCK`: Lock memory pages for DPDK
- `SYS_ADMIN`, `SYS_RAWIO`: Device access
- `NET_RAW`, `SYS_NICE`: Network operations and RT scheduling

### Deployment Model

- **Deployment**: Stateless replicas for load testing
- **Default replicas**: 1 (increase for load testing)
- **Scaling**: Can scale horizontally for multi-cell scenarios

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

- **Documentation**: [OCUDU Project Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **OpenFronthaul**: [O-RAN Alliance Specifications](https://www.o-ran.org/)

## License

BSD 3-Clause Open MPI variant - See LICENSE file for details
