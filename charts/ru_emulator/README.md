# RU Emulator

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying the OCUDU Radio Unit (O-RU) emulator

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened for production use. Use in production environments at your own risk.

## Overview

This chart deploys an O-RU (Open Radio Unit) emulator that communicates with DU units via the OpenFronthaul protocol. It simulates a real Radio Unit for testing and development purposes.

> **ℹ️ Image source**: The OCUDU nightly built images ship the `ru_emulator` binary as part of their build. The chart defaults to that image.

**Capabilities**:
- OpenFronthaul protocol support
- DPDK-based high-performance packet processing
- Multiple cell configuration
- VLAN tagging support

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Container Image**: the chart defaults to the OCUDU image which already ships `/usr/local/bin/ru_emulator`. Override `image.repository` only if using a different build.
2. **Kubernetes**: >= 1.24.0
3. **Network Configuration** (choose one):
   - **hostNetwork mode**: Physical network interface for OpenFronthaul communication
   - **SR-IOV mode** (recommended for production): SR-IOV device plugin deployed in cluster
4. **Non-root prerequisites** (for the default minimum-privilege securityContext):
   - Image has file caps on the binary: `setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/ru_emulator` (OCUDU images include this by default)
   - Node's containerd has `device_ownership_from_security_context = true`
   - If either condition isn't met, override `securityContext` (run as root / broader caps) or add the prerequisites to your cluster
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

## Log Persistence

The RU emulator can persist console output to a log file. By default, logs are written to `/tmp/ru_em.log` inside the container and can be persisted via hostPath or PVC.

Example (hostPath):
```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: /mnt/debugging-logs
  mountPath: /tmp
  preserveOldLogs: true
config:
  log:
    filename: /tmp/ru_em.log
```

If `preserveOldLogs` is `false`, logs are truncated at start.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `"registry.gitlab.com/ocudu/ocudu/ocudu_nightly_avx512"` | Container image repository (OCUDU image ships `ru_emulator`) |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `extraLabels` | object | `{}` | Extra labels applied to the Deployment and Pod template |
| `network.hostNetwork` | bool | `true` | Enable host network (set to `false` for SR-IOV mode) |
| `podSecurityContext.runAsNonRoot` | bool | `true` | Run as non-root (uid 1000); needs the image + containerd prerequisites in the Prerequisites section |
| `securityContext.privileged` | bool | `false` | Privileged mode — disabled by default; override for hostNetwork+igb_uio fallback |
| `securityContext.capabilities.add` | list | `[SYS_NICE, IPC_LOCK]` | Minimum caps for DPDK + RT scheduling (empirically verified) |
| `sriovConfig.enabled` | bool | `false` | Enable SR-IOV device plugin integration |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_netdevice"` | SR-IOV resource name from device plugin |
| `sriovConfig.vfCount` | int | `1` | Number of SR-IOV VFs to request |
| `config.ru_emu.cells` | list | See values.yaml | Cell configuration (interfaces, MAC addresses, VLAN) |
| `config.log.filename` | string | `"/tmp/ru_em.log"` | Log file path inside the container |
| `persistence.enabled` | bool | `true` | Enable persistent storage for logs |
| `persistence.type` | string | `"hostPath"` | Storage type: `pvc` or `hostPath` |
| `persistence.mountPath` | string | `"/tmp"` | Mount path for logs in the container |
| `persistence.preserveOldLogs` | bool | `true` | Append to existing log file if true |
| `replicaCount` | int | `1` | Number of emulated RU instances |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

## Common Configuration Examples

### hostNetwork Mode (Testing/Development — fallback)

Use this when you dont have the SR-IOV Device Plugin install in your cluster. Override the chart's non-root default:

```yaml
# Image defaults to OCUDU; override image.repository only if using a different build.

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

podSecurityContext: {}
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

### SR-IOV Mode (Production — chart default)

The chart ships with the minimum-privilege shape as the default. A values file
mainly needs to toggle network mode and provide cell config.

```yaml
# Image defaults to OCUDU; override image.repository only if using a different build.

network:
  hostNetwork: false

sriovConfig:
  enabled: true
  extendedResourceName: "intel.com/oru"   # adjust to your device-plugin pool
  vfCount: 1

config:
  ru_emu:
    cells:
    - bandwidth: 100
      network_interface: auto     # entrypoint substitutes the allocated VF BDF
      ru_mac_addr: 50:7c:6f:45:44:33
      du_mac_addr: 50:7c:6f:45:44:34
      vlan_tag: 6

# Minimum-privilege security context (chart default — shown for reference).
# Requires image with setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/ru_emulator
# and node containerd with device_ownership_from_security_context = true.
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: true   # required for file caps on execve
  privileged: false
  capabilities:
    drop: ["ALL"]
    add:
      - SYS_NICE
      - IPC_LOCK

resources:
  limits:
    cpu: 4
    memory: 4Gi
    hugepages-1Gi: 2Gi
  requests:
    cpu: 4
    memory: 4Gi
    hugepages-1Gi: 2Gi

nodeSelector:
  kubernetes.io/hostname: worker-node-1
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

**2. SR-IOV Mode**
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

### Why These Capabilities

**SR-IOV Mode (chart default)** — minimum verified set:
- `SYS_NICE`: `sched_setscheduler(SCHED_FIFO)` on DPDK timing / tx-rx threads
- `IPC_LOCK`: `mlock()` on DPDK hugepages

Device access (VFIO group node permissions) is handled by containerd's
`device_ownership_from_security_context = true` flag, not by a capability. The
older `SYS_ADMIN`/`SYS_RAWIO`/`NET_RAW` additions are not required with
vfio-pci + IOMMU + that containerd flag; they were removed in chart 2.4.0.

**hostNetwork Mode (fallback)**: `privileged: true` still needed for direct
hardware access when SR-IOV isn't available. Only use for local testing.

## License

BSD 3-Clause Open MPI variant - See LICENSE file for details
