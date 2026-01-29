# srsRAN Project CU/DU

A Helm chart for deploying the srsRAN Project 5G CU/DU (gNB)

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)

## Documentation

- **[Network Modes](docs/network-modes.md)** - SR-IOV vs hostNetwork deployment modes
- **[SR-IOV Setup](docs/sriov-setup.md)** - Complete SR-IOV configuration guide (recommended for production)
- **[NetworkPolicy](docs/networkpolicy.md)** - Network security and traffic control
- **[Hugepages](docs/hugepages.md)** - Hugepages configuration for DPDK performance
- **[Storage](docs/storage.md)** - PVC and hostPath storage configuration

## Quick Start

### Prerequisites

Before deploying, ensure:

1. **PTP Synchronization**: PTP4l and PHC2SYS services are running with synchronized hardware clock
2. **Network Setup**: Choose your deployment mode:
   - **SR-IOV (Default - Production)**: Requires SR-IOV device plugin (see [SR-IOV Setup](docs/sriov-setup.md))
   - **Host Network (Fallback)**: Direct host access, no SR-IOV needed
3. **DPDK Driver**: Network interface bound to DPDK-compatible driver (`igb_uio` or `vfio-pci`)
4. **Hugepages (Optional)**: Configure hugepages for optimal DPDK performance (see [Hugepages Guide](docs/hugepages.md))

See [Network Modes](docs/network-modes.md) for detailed deployment mode comparison.

### Installation

```bash
# Add the Helm repository (if using remote repo)
helm repo add srsran https://srsran.github.io/srsRAN_Project_helm/

# Install with default values (SR-IOV mode)
helm install my-gnb srsran/srsran-cu-du

# Or install with custom values
helm install my-gnb srsran/srsran-cu-du -f my-values.yaml

# Local installation
cd charts/srsran-project
helm install my-gnb ./
```

### Basic Configuration Examples

**Production deployment with SR-IOV (default)**:
```yaml
network:
  hostNetwork: false  # Default

sriovConfig:
  enabled: true  # Default
  extendedResourceName: "intel.com/intel_sriov_netdevice"

resources:
  limits:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
  requests:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
```

**Quick test with host network**:
```yaml
network:
  hostNetwork: true

sriovConfig:
  enabled: false

resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

## Container Images

Select the appropriate container image based on your CPU:

- **Architectures**: arm64, amd64
- **OS**: Ubuntu 22.04
- **CPU Flags**: AVX512, AVX2, NEON

Find images at: [Docker Hub - softwareradiosystems](https://hub.docker.com/u/softwareradiosystems)

## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `replicaCount` | int | `1` | Number of pod replicas (must be 1 for stateful gNB) |
| `image.repository` | string | `"softwareradiosystems/srsran-project"` | Container image repository |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `network.hostNetwork` | bool | `false` | Enable host network mode (bypasses NetworkPolicy) |
| `sriovConfig.enabled` | bool | `true` | Enable SR-IOV device plugin |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_netdevice"` | SR-IOV resource name |
| `sriovConfig.vfCount` | int | `1` | Number of SR-IOV VFs to request |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only works with hostNetwork: false) |
| `persistence.enabled` | bool | `true` | Enable persistent storage for logs |
| `persistence.type` | string | `"hostPath"` | Storage type: `pvc` or `hostPath` |
| `persistence.pvc.storageClassName` | string | `""` | StorageClass for PVC (empty = default) |
| `persistence.pvc.size` | string | `"10Gi"` | PVC storage size |
| `persistence.hostPath.path` | string | `"/mnt/debugging-logs"` | Host path for logs |
| `resources.limits` | object | `{}` | Resource limits (CPU, memory, hugepages) |
| `resources.requests` | object | `{}` | Resource requests (CPU, memory, hugepages) |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |
| `o1.enable_srs_o1` | bool | `false` | Enable O1 interface (NETCONF management) |
| `config.gnb-config.yml` | string | See values.yaml | gNB configuration file |

For complete parameter documentation, see:
- [Network configuration](docs/network-modes.md)
- [Storage configuration](docs/storage.md)
- [Performance tuning](docs/hugepages.md)
- [Security](docs/networkpolicy.md)

### gNB Configuration

The gNB configuration file `gnb-config.yml` is defined in `values.yaml`. Refer to the [srsRAN Project Configuration Reference](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html) for detailed configuration options.

## Upgrading

```bash
# Upgrade to latest version
helm upgrade my-gnb srsran/srsran-cu-du

# Upgrade with new values
helm upgrade my-gnb srsran/srsran-cu-du -f my-values.yaml
```

## Uninstalling

```bash
helm uninstall my-gnb
```

This removes all Kubernetes resources associated with the chart.

## Support

- **Documentation**: [srsRAN Project Docs](https://docs.srsran.com)
- **Issues**: [GitHub Issues](https://github.com/srsran/srsRAN_Project_helm/issues)
- **Community**: [srsRAN Discussions](https://github.com/srsran/srsRAN_Project/discussions)

## License

AGPL-3.0 - See LICENSE file for details
