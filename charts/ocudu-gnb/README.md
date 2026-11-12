# OCUDU gNB CU/DU

A Helm chart for deploying the OCUDU 5G CU/DU (gNB)

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)
[![CNTi essential](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-gnb%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)
[![CNTi workload](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-gnb-workload%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)

## Documentation

- **[Security Guide](docs/security.md)** - Pod Security Standards, service account, and PDB configuration ⭐
- **[Network Modes](docs/network-modes.md)** - SR-IOV vs hostNetwork deployment modes
- **[SR-IOV Setup](docs/sriov-setup.md)** - Complete SR-IOV configuration guide (recommended for production)
- **[NetworkPolicy](docs/networkpolicy.md)** - Network security and traffic control
- **[Hugepages](docs/hugepages.md)** - Hugepages configuration for DPDK performance
- **[Storage](docs/storage.md)** - PVC and hostPath storage configuration
- **[O1 / NETCONF](docs/o1.md)** - O1 interface, optional TLS, and persistent sidecar logs
- **[IPsec](docs/ipsec.md)** - Protect Xn with IKEv2 and tunnel-mode ESP

## Quick Start

### Prerequisites

Before deploying, ensure:

1. **PTP Synchronization**: PTP4l and PHC2SYS services are running with synchronized hardware clock
2. **Network Setup**: Choose your deployment mode:
   - **SR-IOV (Default)**: Requires SR-IOV device plugin (see [SR-IOV Setup](docs/sriov-setup.md))
   - **Host Network (Fallback)**: Direct host access, no SR-IOV needed
3. **DPDK Driver**: Network interface bound to `vfio-pci` (`igb_uio` needs a privileged container)
4. **Hugepages**: Required for DPDK (see [Hugepages Guide](docs/hugepages.md))
5. **CPU pinning**: The kubelet `static` CPU manager policy and a Guaranteed pod; the DPDK image refuses to start when its CPU set does not match its CPU request
6. **Non-root prerequisites** (for the default minimum-privilege securityContext to work):
   - Image has file caps on the binary: `setcap cap_sys_nice,cap_ipc_lock,cap_perfmon+p /usr/local/bin/gnb`
   - Node's containerd has `device_ownership_from_security_context = true`
   - Namespace enforces the Privileged Pod Security level: Baseline rejects `SYS_NICE` and `IPC_LOCK`

   See [Security Guide](docs/security.md) for the full rationale. If any of these is not met, override the chart's `securityContext` with a broader cap set or run as root.

See [Network Modes](docs/network-modes.md) for detailed deployment mode comparison.

### Installation

```bash
# Add the Helm repository (if using remote repo)
# OCI registry - no need to add repo

# Install; my-values.yaml must set resources (see below)
helm install ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb -f my-values.yaml

# Local installation
cd charts/ocudu-gnb
helm install ocudu-gnb ./ -f my-values.yaml
```

The default `resources` request and limit 4 CPUs and 4Gi. `resources.requests` and
`resources.limits` must both set `cpu` and `memory`; the chart does not render without them.
Equal requests and limits give the pod Guaranteed QoS.

After installation, Helm lists the Services the release created.

```bash
kubectl get pod -l app.kubernetes.io/name=ocudu-gnb
kubectl logs -l app.kubernetes.io/name=ocudu-gnb -c ocudu-gnb -f
```

A successful start logs `==== gNB started ===`.

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

config:
  gnb-config.yml: |-
    hal:
      eal_args: "--lcores (0-1)@(0-11)"
    # ...rest of the config...
```

With a VF the config must have `hal.eal_args` with an `@(...)` CPU list; the entrypoint
fills in the pod's CPUs and refuses to start without it. See [SR-IOV Setup](docs/sriov-setup.md).

**Quick test with host network**:
```yaml
network:
  hostNetwork: true

sriovConfig:
  enabled: false

securityContext:
  privileged: true  # the DPDK datapath needs it without SR-IOV
  capabilities:
    add:
      - SYS_NICE
      - NET_ADMIN

resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

**Use tini instead of catatonit as PID 1**:
```yaml
initCommand:
  - /usr/bin/tini
  - -s
  - -g
  - --
```

`initCommand` defaults to catatonit. Override it when the image provides a different init binary. Availability of packaged catatonit and tini varies by OS:

| OS | catatonit | tini |
|----|-----------|------|
| Ubuntu 24.04 | Yes (`universe`) | Yes (`universe`) |
| Ubuntu 26.04 | Yes (`universe`) | Yes (`universe`) |
| CentOS Stream 10 | Yes (`AppStream`) | No |
| UBI 10 | Yes (`AppStream`) | No |
| Hummingbird | Yes | No |
| Arch Linux (2026.08.01) | Yes (`extra`) | AUR only |

**External 5G Core with LoadBalancer**:
```yaml
# N2/N3 Service - Expose gNB to external 5G Core
service:
  enabled: true
  type: LoadBalancer
  loadBalancerIP: "10.0.0.100"  # Optional, cluster-dependent
  advertisedAddress: "10.0.0.100"  # Defaults to loadBalancerIP when empty
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

# O1 Service - Expose NETCONF to external ONAP SMO (start from values-o1.yaml)
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

**Metrics** (`grafana-ocudu` chart):

The gNB reports metrics per layer. `config.gnb-config.yml` lists every
`metrics.layers` switch with its default; set a switch to `true` to report that
layer. For what each switch reports, see the
[OCUDU Configuration Reference](https://docs.ocudu.org/user_manual/config_reference/).

To send the metrics to Grafana, enable `metricsService`, JSON metrics and the
remote control server, and add `PERFMON` for the power metric:

```yaml
metricsService:
  enabled: true
securityContext:
  capabilities:
    add: [SYS_NICE, IPC_LOCK, PERFMON]   # list replaces the default: keep SYS_NICE and IPC_LOCK
config:
  gnb-config.yml: |-
    # ...rest of the config...
    metrics:
      enable_json: true
      layers:
        enable_app_usage: true   # CPU, memory, power and buffer pool
        enable_rlc: true         # example: add a layer that is off by default
    remote_control:
      enabled: true
      bind_addr: 0.0.0.0
      port: 8001
```

Point the `grafana-ocudu` chart's `gnbs[].wsUrl` at the metrics service.

`enable_app_usage` reports CPU, memory, power and buffer-pool metrics. The power reading needs the
`PERFMON` capability, which the chart does not grant by default (see
[docs/security.md](docs/security.md)), and a CPU with RAPL energy counters (Intel, recent AMD).
Without them, the power panels show 0 W.

## Container Images

Select the appropriate container image based on your CPU:

- **Architectures**: arm64, amd64
- **OS**: Ubuntu 24.04
- **CPU Flags**: AVX512, AVX2, NEON

Find images at: [GitLab container registry](https://gitlab.com/ocudu/ocudu/container_registry/).
The default is `registry.gitlab.com/ocudu/ocudu/images/gnb-dpdk`, tagged
`ubuntu-24.04-<avx512|avx2|neon>-latest`, which moves to the newest nightly build. Pin a
`-<date>_<commit>` or `-<date>_<commit>-stable` tag in production.

## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `replicaCount` | int | `1` | Number of pod replicas (must be 1 for stateful gNB) |
| `image.repository` | string | `"registry.gitlab.com/ocudu/ocudu/images/gnb-dpdk"` | Container image repository |
| `image.tag` | string | `"ubuntu-24.04-avx512-latest"` | Image tag |
| `image.pullPolicy` | string | `"Always"` | Image pull policy |
| `extraLabels` | object | `{}` | Extra labels applied to the Deployment and Pod template |
| `initCommand` | list | `["/usr/bin/catatonit", "-g", "--"]` | Init process command used as container PID 1 |
| `runtimeClassName` | string | `""` | RuntimeClass of the pod, e.g. one from an OpenShift PerformanceProfile |
| `configmap.*.nameOverride` | string | `""` | Fixed, mutable ConfigMap name; by default ConfigMaps are immutable and named after a hash of their data |
| `securityContext.readOnlyRootFilesystem` | bool | `true` | Read-only root; `gnb` writes only to `/tmp`, `/run/ocudu` and `persistence.mountPath` |
| `network.hostNetwork` | bool | `false` | Enable host network mode (bypasses NetworkPolicy) |
| `sriovConfig.enabled` | bool | `true` | Enable SR-IOV device plugin |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_netdevice"` | SR-IOV resource name; the chart requests one VF of it |
| `serviceAccount.annotations` | object | `{}` | Annotations on the gNB pod's ServiceAccount (no token is mounted, no Role is bound) |
| `startupProbe.enabled` | bool | `true` | Gate liveness/readiness until `gnb` is running |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `podDisruptionBudget.unhealthyPodEvictionPolicy` | string | `"AlwaysAllow"` | Pod eviction policy |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only works with hostNetwork: false) |
| `ipsec.enabled` | bool | `false` | Protect Xn with IKEv2 and tunnel-mode ESP — see [`docs/ipsec.md`](docs/ipsec.md) |
| `service.enabled` | bool | `false` | Enable the Service for N2/N3 interfaces |
| `service.type` | string | `"LoadBalancer"` | Service type: `LoadBalancer`, `NodePort`, or `ClusterIP` |
| `service.externalIPs` | list | `[]` | IP addresses routed to the N2/N3 Service by the surrounding network |
| `service.advertisedAddress` | string | `""` | N3 address advertised to the core; defaults to `loadBalancerIP` |
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
| `o1.netconfServer.tls.clientCertSecret` | string | `""` | Secret with the adapter's client identity (`ca.crt`, `client.crt`, `client.key`); required when `certSecret` is set |
| `o1.netconfServer.ssh.hostKeySecret` | string | `""` | Secret with `ssh_host_{ed25519,ecdsa}_key` + `known_hosts`; omit to use the host key generated in the netconf image and skip host key verification. Needs a netconf-server image that supports `--ssh-hostkey-dir` (see `docs/o1.md`) |
| `o1.netconfServer.ssh.username` | string | `"netconf"` | NETCONF SSH user with password authentication (RFC 9644 local user) for clients that only implement the SSH `password` method; empty = disabled |
| `o1.netconfServer.ssh.passwordSecret` | string | `""` | Existing Secret with key `password` holding the NETCONF user's password (production); cleartext becomes `$0$<pw>`, a `$...` crypt hash passes through verbatim |
| `o1.netconfServer.ssh.password` | string | `"netconf"` | Dev/test cleartext password the chart renders into a Secret itself; ignored when `passwordSecret` is set. Change it in production |
| `o1.o1Adapter.fileLog.enabled` | bool | `false` | Persist the o1 adapter output to a file under `persistence.mountPath` |
| `o1.netconfServer.fileLog.enabled` | bool | `false` | Persist the netconf-server output to a timestamped file under `persistence.mountPath` |
| `o1.netconfServer.persistence.enabled` | bool | `true` | Keep the running config set over NETCONF across pod restarts in a PersistentVolumeClaim; every helm upgrade starts from `o1Config` again |
| `o1.netconfServer.persistence.storageClassName` | string | `""` | StorageClass of the claim; empty uses the cluster default |
| `o1.netconfServer.persistence.size` | string | `"10Mi"` | Size of the claim |
| `o1.netconfServer.persistence.existingClaim` | string | `""` | Existing PersistentVolumeClaim to use instead of creating one |
| `persistence.enabled` | bool | `false` | Enable persistent storage for logs (otherwise `emptyDir`) |
| `persistence.type` | string | `"pvc"` | Storage type: `pvc` or `hostPath` |
| `persistence.pvc.storageClassName` | string | `""` | StorageClass for PVC (empty = default) |
| `persistence.pvc.size` | string | `"10Gi"` | PVC storage size |
| `persistence.hostPath.path` | string | `"/mnt/debugging-logs"` | Host path for logs |
| `persistence.preserveOldLogs` | bool | `true` | Give each run's log files a timestamp and link the newest as `current` |
| `resources.limits` | object | 4 CPUs, 4Gi | Resource limits (CPU, memory, hugepages); `cpu` and `memory` are required |
| `resources.requests` | object | 4 CPUs, 4Gi | Resource requests (CPU, memory, hugepages); `cpu` and `memory` are required |
| `nodeSelector` | object | `{}` | Node selector for pod assignment |
| `tolerations` | list | `[]` | Tolerations for pod assignment |
| `affinity` | object | `{}` | Affinity rules for pod assignment |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints for pod assignment |
| `priorityClassName` | string | `""` | Priority class assigned to the pod |
| `config.gnb-config.yml` | string | See values.yaml | gNB configuration file |

The `o1.*` rows other than `o1.enable_ocudu_o1` give the defaults of
[`values-o1.yaml`](values-o1.yaml); install O1 with `-f values-o1.yaml`.

For complete parameter documentation, see:
- [Security configuration](docs/security.md) - service account, PDB, Pod Security Standards
- [Network configuration](docs/network-modes.md)
- [Storage configuration](docs/storage.md)
- [Performance tuning](docs/hugepages.md)
- [Network policies](docs/networkpolicy.md)

### gNB Configuration

The gNB configuration file `gnb-config.yml` is defined in `values.yaml`. Refer to the [OCUDU Configuration Reference](https://docs.ocudu.org/user_manual/config_reference/) for detailed configuration options.

## Upgrading

```bash
# Upgrade; pass the values file used for the install
helm upgrade ocudu-gnb oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb -f my-values.yaml
```

ConfigMaps are immutable and named after a hash of their data, so a config change rolls
the pod and a live `kubectl edit` is rejected. Roll back with `helm rollback`.

`persistence.enabled` defaults to `false`: without it in your values, logs go to an
`emptyDir`. With the read-only root, every log, trace and pcap path in the config must be
under `/tmp`, `/run/ocudu` or `persistence.mountPath`, or the chart does not render.

If your values file overrides `config.gnb-config.yml`, new defaults in the chart's
config (for example `metrics.layers.enable_app_usage: true`) do not reach your
deployment. Compare your config with the chart's `values.yaml` and copy over the
settings you want.

## Uninstalling

```bash
helm uninstall ocudu-gnb
```

This removes all Kubernetes resources associated with the chart.

## Support

- **Documentation**: [OCUDU Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Issues**: [GitLab Issues](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/issues)
- **OCUDU issues**: [OCUDU on GitLab](https://gitlab.com/ocudu/ocudu/-/issues)

## License

BSD-3-Clause-Open-MPI - See LICENSE file for details
