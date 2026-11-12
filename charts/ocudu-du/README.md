
# ocudu-du

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)
[![CNTi essential](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-du%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)
[![CNTi workload](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-du-workload%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)

A Helm chart for deploying the OCUDU 5G DU (Distributed Unit)

## Overview

The DU runs the `odu` binary. It terminates F1-C (F1AP) and F1-U (GTP-U) toward the CU, or
toward CU-CP and CU-UP, and drives the radio unit.

## Prerequisites

By default the pod requests one SR-IOV VF (`sriovConfig.extendedResourceName`,
`intel.com/intel_sriov_dpdk`) for an Open Fronthaul radio driven by DPDK. Without the SR-IOV
device plugin the pod stays `Pending`. Set `sriovConfig.enabled: false` when there is no
fronthaul NIC, for example with `ru_dummy` or a USRP.

For DPDK, see the [SR-IOV guide](../../docs/sriov-setup.md) and the
[hugepages guide](../../docs/hugepages.md).

## Installing the Chart

```bash
helm install ocudu-du oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-du --version 1.14.0 -f my-values.yaml
```

The default `resources` request and limit 4 CPUs and 4Gi. `resources.requests` and
`resources.limits` must both set `cpu` and `memory`; the chart does not render without them.

**Local installation**:
```bash
cd charts/ocudu-du
helm install ocudu-du ./ -f my-values.yaml
```

## Verifying Installation

```bash
# Check pod status
kubectl get pod -l app.kubernetes.io/name=ocudu-du

# View logs
kubectl logs -l app.kubernetes.io/name=ocudu-du -f
```

A successful start logs `==== DU started ===`.

## Uninstalling the Chart

```bash
helm uninstall ocudu-du
```

This removes all Kubernetes resources associated with the chart.

## Upgrading

```bash
helm upgrade ocudu-du oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-du --version 1.14.0 -f my-values.yaml
```

The chart sets `deploymentStrategy.type: Recreate` by default — the old pod
is fully terminated before the new one starts, since this is a stateful
workload that should not run overlapping old/new pods.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `image.repository` | string | `"registry.gitlab.com/ocudu/ocudu/images/du-dpdk"` | Container image repository; `du-uhd` for USRP radios |
| `image.tag` | string | `"ubuntu-24.04-avx512-latest"` | Image tag; pick the CPU variant (`avx512`, `avx2`, `neon`) the node supports |
| `network.hostNetwork` | bool | `false` | Enable host network mode |
| `network.ipFamilyPolicy` | string | `"PreferDualStack"` | IP family policy of the Services except the IPsec one; `""` leaves it to the cluster |
| `sriovConfig.enabled` | bool | `true` | Request one SR-IOV VF from the device plugin |
| `sriovConfig.extendedResourceName` | string | `"intel.com/intel_sriov_dpdk"` | Resource name advertised by the SR-IOV device plugin |
| `f1cService.enabled` | bool | `true` | Enable F1-C (F1AP) Service |
| `f1uService.enabled` | bool | `true` | Enable F1-U (GTP-U) Service |
| `networkPolicy.enabled` | bool | `false` | Enable NetworkPolicy (only effective when `hostNetwork: false`) |
| `networkPolicy.egress.dnsTo` | list | cluster DNS pods | Where DNS lives; set `[]` to allow port 53 to any destination |
| `ipsec.enabled` | bool | `false` | Protect F1-C and F1-U with IKEv2 and tunnel-mode ESP — see [`docs/ipsec.md`](docs/ipsec.md) |
| `ipsec.peers` | map | `{}` | One entry per peer: `id`, plus `address` on the side that dials |
| `ipsec.connections` | map | `{}` | One entry per protected interface: `peer`, `protocol`, `local`, `remote` |
| `ipsec.certSecret` | string | `""` | Secret holding this pod's identity (`tls.crt`, `tls.key`, `ca.crt`) |
| `ipsec.certManager.enabled` | bool | `false` | Have cert-manager issue `certSecret` instead of bringing your own |
| `metricsService.enabled` | bool | `false` | Enable the metrics/remote-control WebSocket endpoint. For Grafana and the power metric, see [Metrics with Grafana](#metrics-with-grafana-grafana-ocudu-chart) |
| `persistence.enabled` | bool | `false` | Enable persistent storage for logs (otherwise `emptyDir`) |
| `persistence.type` | string | `"pvc"` | Storage type: `pvc` or `hostPath` |
| `persistence.preserveOldLogs` | bool | `true` | Give each run's log files a timestamp and link the newest as `current` |
| `resources` | object | 4 CPUs, 4Gi | Requests and limits; `cpu` and `memory` are required in both, hugepages are optional |
| `replicaCount` | int | `1` | Number of DU replicas; a DU driving radio hardware cannot be replicated |
| `runtimeClassName` | string | `""` | RuntimeClass of the pod, e.g. one from an OpenShift PerformanceProfile |
| `serviceAccount.annotations` | object | `{}` | Annotations on the DU pod's ServiceAccount (no token is mounted, no Role is bound) |
| `startupProbe.enabled` | bool | `true` | Gate liveness/readiness until `odu` is running |
| `priorityClassName` | string | `""` | Priority class assigned to the pod |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints for pod assignment |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `deploymentStrategy.type` | string | `"Recreate"` | Deployment update strategy |
| `o1.enable_ocudu_o1` | bool | `false` | Enable the O1 interface (NETCONF management) |
| `o1.o1Port` | int | `830` | NETCONF SSH port — image-coupled, see below |
| `o1.netconfServer.service.type` | string | `"NodePort"` | O1 service type: `NodePort`, `LoadBalancer`, or `ClusterIP` |
| `o1.netconfServer.tls.enabled` | bool | `false` | Enable the NETCONF-over-TLS endpoint on port 6513 |
| `o1.netconfServer.ssh.username` | string | `"netconf"` | NETCONF SSH user with password authentication; empty = disabled |
| `o1.netconfServer.ssh.password` | string | `"netconf"` | Dev/test cleartext password; use `passwordSecret` in production |
| `o1.netconfServer.persistence.enabled` | bool | `true` | Keep the running config set over NETCONF across pod restarts in a PersistentVolumeClaim |
| `config.du-config.yml` | string | See `values.yaml` | DU application configuration file |
| `o1Config.o1-config.xml` | string | See `values-o1.yaml` | ManagedElement template served by the netconf-server (replaces `config` in O1 mode) |

The `o1.*` and `o1Config` keys are absent from `values.yaml` — O1 is off unless
they are supplied. The defaults listed above are the ones shipped in
[`values-o1.yaml`](values-o1.yaml).

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml), or
[`values-o1.yaml`](values-o1.yaml) for the O1-enabled variant.

## Common Configuration Examples

### Open Fronthaul with an SR-IOV VF and DPDK

```yaml
sriovConfig:
  enabled: true
  extendedResourceName: intel.com/intel_sriov_dpdk

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
  du-config.yml: |-
    hal:
      eal_args: "--lcores (0-1)@(0-11)"
    ru_ofh:
      cells:
        - network_interface: 0000:00:00.0
          du_mac_addr: 00:00:00:00:00:00
          ru_mac_addr: <RU MAC>
    # f1ap, f1u, cell_cfg, log ...
```

With `hostNetwork: false` the entrypoint fills in what only the pod knows: the VF's PCI
address as `network_interface`, its MAC as `du_mac_addr`, and the container's CPUs inside
`@(...)` in `hal.eal_args`. An `ru_ofh` section with an SR-IOV VF and no `hal` section is
refused at startup. With `hostNetwork: true`, set `network_interface` yourself.

Hugepage volumes are added when `resources` asks for `hugepages-1Gi` or `hugepages-2Mi`.

### Without a radio (`ru_dummy`)

```yaml
sriovConfig:
  enabled: false

config:
  du-config.yml: |-
    f1ap:
      addrs: <CU F1-C Service>
    ru_dummy:
      dl_processing_delay: 1
    cell_cfg:
      dl_arfcn: 632628
      band: 78
      channel_bandwidth_MHz: 20
      common_scs: 30
      plmn: "00101"
      tac: 7
      pci: 1
```

### hostPath persistence

```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/debugging-logs"
    type: DirectoryOrCreate
```

The target directory must exist and be owned by uid 1000 on the node before
deploying — `fsGroup` does not apply to hostPath volumes.

A hostPath volume ties the pod to whichever node holds that directory. A DU pinned to
its fronthaul NIC is tied to that node anyway; otherwise treat hostPath as a
local-debugging configuration.

### Metrics with Grafana (`grafana-ocudu` chart)

The DU sends its metrics to the `grafana-ocudu` chart like the gNB does. Enable
`metricsService`, JSON metrics and the remote control server. The power metric needs
`PERFMON` in `securityContext.capabilities.add`:

```yaml
metricsService:
  enabled: true
securityContext:
  capabilities:
    add: [SYS_NICE, IPC_LOCK, PERFMON]   # list replaces the default: keep SYS_NICE and IPC_LOCK
config:
  du-config.yml: |-
    # ...rest of the config...
    metrics:
      enable_json: true
      layers:
        enable_app_usage: true   # CPU, memory, power and buffer pool
    remote_control:
      enabled: true
      bind_addr: 0.0.0.0
      port: 8001
```

Add an entry to the `grafana-ocudu` chart's `gnbs[]` list with `wsUrl` pointing at this
chart's `-metrics` Service on port 8001. Without `PERFMON` the power panels show 0 W.

## IPsec

F1-C and F1-U can be carried over IKEv2 with tunnel-mode ESP, by a strongSwan sidecar that runs
in this pod. Off by default, and nothing renders until `ipsec.enabled` is set.

The DU dials the CU's headless service:

```yaml
f1cService:
  enabled: false
f1uService:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certManager:
    enabled: true
    issuerRef:
      name: <your issuer>
  localId: du
  peers:
    cu:
      id: cu
      address: <release>-ocudu-cu-ipsec
  connections:
    f1c: {protocol: sctp, local: 100.64.10.2, remote: 100.64.10.1}
    f1u: {protocol: udp, local: 100.64.30.2, remote: 100.64.30.1}
```

The application has to bind the protected addresses, and F1-U has to move off UDP 2152
(`f1u.bind_port` and `peer_port`); the chart refuses to render otherwise.
[`docs/ipsec.md`](docs/ipsec.md) has the worked example, the requirements this places on
the cluster, and the full list of what the chart refuses.

## Security Context and Capabilities

The chart defaults are otherwise restrictive — non-root pod, read-only root
filesystem, every capability dropped except the two below, no service account
token, no RBAC, no privileged container — but two settings are deliberately not
at their most restrictive value:

```yaml
securityContext:
  allowPrivilegeEscalation: true
  capabilities:
    add: [SYS_NICE, IPC_LOCK]
```

- `SYS_NICE`: `odu` runs its real-time threads at `SCHED_FIFO` priority. Without it,
  `odu` prints `Scheduling priority of thread "..." not changed`, and the fronthaul
  misses its deadlines.
- `IPC_LOCK`: DPDK pins its hugepage memory for DMA through VFIO.
- `PERFMON` (not added by default): only for the RAPL power metric; `odu` runs without it.

The image bakes all three into the binary as permitted-only *file* capabilities
(`setcap cap_sys_nice,cap_ipc_lock,cap_perfmon+p`), and `odu` starts with whichever of
them the container grants. `allowPrivilegeEscalation: false` sets `NO_NEW_PRIVS`, under
which the kernel ignores file capabilities, so the process would start without any of them.

A non-root pod can only open the VF's `/dev/vfio` device when containerd sets
`device_ownership_from_security_context = true` on the node.

With the read-only root filesystem, `odu` writes only to `/tmp`, `/run/ocudu`
(DPDK's runtime files) and `persistence.mountPath`, which are volumes. Point logs and
pcaps at `persistence.mountPath`.

See the [security guide](../../docs/security.md) for the details.

## O1 / NETCONF Interface

Enable the O1 interface by setting `o1.enable_ocudu_o1: true` and using
[`values-o1.yaml`](values-o1.yaml) as a base:

```bash
helm install ocudu-du ./ -f values-o1.yaml
```

In O1 mode the pod gains two sidecars — `ocudu-o1-adapter` and `netconf-server`.
The `config` ConfigMap is replaced by `o1Config` (an `o1-config.xml`
ManagedElement template with a `GNBDUFunction`): the adapter renders
`du-config.yml` from the NETCONF running config into a shared `emptyDir`, and the
entrypoint waits for that file (up to `CONFIG_CREATE_TIMEOUT`, 120s) before starting
`odu`. Liveness therefore tracks the adapter's `/config-healthy` endpoint.

`o1.o1Port` (830), `o1.healthcheckPort` (5000) and the TLS port (6513) are built
into the sidecar images. Treat them as fixed unless you also change
`o1.o1Adapter.image` / `o1.netconfServer.image`.

TLS, the SSH password user, persistent sidecar logs and the kept running config are
described in the [O1 guide](../../docs/o1.md).

## Support

- **Documentation**: [OCUDU Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Issues**: [GitLab Issues](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/issues)

## License

BSD-3-Clause-Open-MPI - See LICENSE file for details
