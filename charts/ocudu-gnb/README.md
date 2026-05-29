# OCUDU gNB CU/DU

A Helm chart for deploying the OCUDU 5G CU/DU (gNB)

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)

## Documentation

- **[Security Guide](docs/security.md)** - Pod Security Standards, RBAC, and PDB configuration ⭐
- **[Network Modes](docs/network-modes.md)** - SR-IOV vs hostNetwork deployment modes
- **[SR-IOV Setup](docs/sriov-setup.md)** - Complete SR-IOV configuration guide (recommended for production)
- **[NetworkPolicy](docs/networkpolicy.md)** - Network security and traffic control
- **[Hugepages](docs/hugepages.md)** - Hugepages configuration for DPDK performance
- **[Storage](docs/storage.md)** - PVC and hostPath storage configuration
- **[O1 / NETCONF](docs/o1.md)** - O1 interface and optional TLS configuration

## Quick Start

### Prerequisites

Before deploying, ensure:

1. **PTP Synchronization**: PTP4l and PHC2SYS services are running with synchronized hardware clock
2. **Network Setup**: Choose your deployment mode:
   - **SR-IOV (Default)**: Requires SR-IOV device plugin (see [SR-IOV Setup](docs/sriov-setup.md))
   - **Host Network (Fallback)**: Direct host access, no SR-IOV needed
3. **DPDK Driver**: Network interface bound to DPDK-compatible driver (`igb_uio` or `vfio-pci`)
4. **Hugepages**: Configure hugepages for optimal DPDK performance (see [Hugepages Guide](docs/hugepages.md))
5. **Non-root prerequisites** (for the default minimum-privilege securityContext to work):
   - Image has file caps on the binary: `setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/gnb`
   - Node's containerd has `device_ownership_from_security_context = true`

   See [Security Guide](docs/security.md) for the full rationale. If either condition is not met, override the chart's `securityContext` with a broader cap set or run as root.

See [Network Modes](docs/network-modes.md) for detailed deployment mode comparison.

### Installation

```bash
# Add the Helm repository (if using remote repo)
# OCI registry - no need to add repo

# Install with default values (SR-IOV mode)
helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.0.0

# Or install with custom values
helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.0.0 -f my-values.yaml

# Local installation
cd charts/ocudu-gnb
helm install ocudu-gnb ./
```

After installation, Helm will display **post-install notes** with:
- Deployment configuration summary
- Service access information
- Verification commands
- Next steps and documentation links

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

**External 5G Core with LoadBalancer**:
```yaml
# N2/N3 Service - Expose gNB to external 5G Core
service:
  enabled: true
  type: LoadBalancer
  loadBalancerIP: "10.0.0.100"  # Optional, cluster-dependent
  loadBalancerClass: "metallb"  # Optional, for multiple LB providers
  externalTrafficPolicy: Local  # Preserves source IP
  sessionAffinity: None
  ports:
    n2:  # NGAP control plane to AMF
      enabled: true
      port: 38412
      protocol: SCTP
    n3:  # GTP-U user plane to UPF
      enabled: true
      port: 2152
      protocol: UDP

# Metrics Service - Expose metrics to external Telegraf
metricsService:
  enabled: true
  type: LoadBalancer
  loadBalancerIP: "10.0.0.102"  # Optional
  loadBalancerClass: "metallb"  # Optional
  externalTrafficPolicy: Cluster
  port: 8001

# O1 Service - Expose NETCONF to external ONAP SMO
o1:
  enable_ocudu_o1: true
  netconfServer:
    service:
      type: LoadBalancer
      loadBalancerIP: "10.0.0.103"  # Optional
      loadBalancerClass: "metallb"  # Optional
      externalTrafficPolicy: Cluster
```

> **Note**: LoadBalancer services require a LoadBalancer controller (e.g., MetalLB, cloud provider) in your cluster. Without one, services will remain in `<pending>` state. For clusters without LoadBalancer support, use `NodePort` instead.

## Container Images

Select the appropriate container image based on your CPU:

- **Architectures**: arm64, amd64
- **OS**: Ubuntu 24.04
- **CPU Flags**: AVX512, AVX2, NEON

Find images at: [Docker Hub - softwareradiosystems](https://hub.docker.com/u/softwareradiosystems)

## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `replicaCount` | int | `1` | Number of pod replicas (must be 1 for stateful gNB) |
| `image.repository` | string | `"softwareradiosystems/ocudu-gnb"` | Container image repository |
| `image.tag` | string | Chart appVersion | Image tag |
| `image.pullPolicy` | string | `"IfNotPresent"` | Image pull policy |
| `extraLabels` | object | `{}` | Extra labels applied to the Deployment and Pod template |
| `network.hostNetwork` | bool | `false` | Enable host network mode (bypasses NetworkPolicy) |
| `sriovConfig.enabled` | bool | `true` | Enable SR-IOV device plugin |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_netdevice"` | SR-IOV resource name (specify resources manually in resources section) |
| `rbac.create` | bool | `true` | Create RBAC Role and RoleBinding |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `podDisruptionBudget.unhealthyPodEvictionPolicy` | string | `"AlwaysAllow"` | Pod eviction policy |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only works with hostNetwork: false) |
| `service.enabled` | bool | `false` | Enable LoadBalancer service for N2/N3 interfaces |
| `service.type` | string | `"LoadBalancer"` | Service type: `LoadBalancer`, `NodePort`, or `ClusterIP` |
| `service.loadBalancerIP` | string | `""` | LoadBalancer IP address (optional, cluster-dependent) |
| `service.loadBalancerClass` | string | `""` | LoadBalancer class (optional, for multiple LB providers) |
| `service.externalTrafficPolicy` | string | `"Cluster"` | External traffic policy: `Cluster` or `Local` |
| `service.sessionAffinity` | string | `"None"` | Session affinity: `None` or `ClientIP` |
| `metricsService.enabled` | bool | `false` | Enable metrics service |
| `metricsService.type` | string | `"ClusterIP"` | Service type: `LoadBalancer`, `NodePort`, or `ClusterIP` |
| `metricsService.loadBalancerIP` | string | `""` | LoadBalancer IP (when type is LoadBalancer) |
| `metricsService.loadBalancerClass` | string | `""` | LoadBalancer class (optional) |
| `metricsService.externalTrafficPolicy` | string | `"Cluster"` | External traffic policy |
| `o1.enable_ocudu_o1` | bool | `false` | Enable O1 interface (NETCONF management) |
| `o1.netconfServer.service.type` | string | `"NodePort"` | O1 service type |
| `o1.netconfServer.service.loadBalancerIP` | string | `""` | LoadBalancer IP (when type is LoadBalancer) |
| `o1.netconfServer.service.loadBalancerClass` | string | `""` | LoadBalancer class (optional) |
| `o1.netconfServer.tls.enabled` | bool | `false` | Enable NETCONF-over-TLS endpoint on port 6513 |
| `o1.netconfServer.tls.certSecret` | string | `""` | Secret name with `ca.crt`, `server.crt`, `server.key`; omit for auto-generated self-signed certs |
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
| `o1.enable_ocudu_o1` | bool | `false` | Enable O1 interface (NETCONF management) |
| `config.gnb-config.yml` | string | See values.yaml | gNB configuration file |

For complete parameter documentation, see:
- [Security configuration](docs/security.md) - RBAC, PDB, Pod Security Standards
- [Network configuration](docs/network-modes.md)
- [Storage configuration](docs/storage.md)
- [Performance tuning](docs/hugepages.md)
- [Network policies](docs/networkpolicy.md)

### gNB Configuration

The gNB configuration file `gnb-config.yml` is defined in `values.yaml`. Refer to the [OCUDU Configuration Reference](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/projects/project/en/latest/user_manuals/source/config_ref.html) for detailed configuration options.

## Upgrading

```bash
# Upgrade to latest version
helm upgrade ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.0.0

# Upgrade with new values
helm upgrade ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb --version 3.0.0 -f my-values.yaml
```

## Uninstalling

```bash
helm uninstall my-gnb
```

This removes all Kubernetes resources associated with the chart.

## Support

- **Documentation**: [OCUDU Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Issues**: [GitLab Issues](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/issues)
- **Community**: [OCUDU Discussions](https://gitlab.com/ocudu/ocudu/-/issues)

## License

BSD-3-Clause-Open-MPI - See LICENSE file for details
