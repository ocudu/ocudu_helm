
# ocudu-cu

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)
[![CNTi essential](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-cu%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)
[![CNTi workload](https://img.shields.io/endpoint?url=https%3A%2F%2Fgitlab.com%2Fapi%2Fv4%2Fprojects%2F77870615%2Fpackages%2Fgeneric%2Fcnti-badge%2Focudu-cu-workload%2Fcnti-badge.json)](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/pipelines?ref=main)

A Helm chart for deploying the OCUDU 5G CU (Central Unit)

## Overview

The CU runs CU-CP and CU-UP in one pod, as the `ocu` binary. It terminates N2 (NGAP, toward
the AMF), N3 (GTP-U, toward the UPF), F1-C (F1AP, toward the DU) and F1-U (GTP-U, toward the
DU). To run CU-CP and CU-UP as separate pods, use the `ocudu-cu-cp` and `ocudu-cu-up` charts.

## Installing the Chart

```bash
helm install ocudu-cu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu --version 1.15.0 -f my-values.yaml
```

The default `resources` request and limit 2 CPUs and 4Gi. `resources.requests` and
`resources.limits` must both set `cpu` and `memory`; the chart does not render without them.

**Local installation**:
```bash
cd charts/ocudu-cu
helm install ocudu-cu ./ -f my-values.yaml
```

## Verifying Installation

```bash
# Check pod status
kubectl get pod -l app.kubernetes.io/name=ocudu-cu

# View logs
kubectl logs -l app.kubernetes.io/name=ocudu-cu -f
```

A successful start logs `==== CU started ===`.

## Uninstalling the Chart

```bash
helm uninstall ocudu-cu
```

This removes all Kubernetes resources associated with the chart.

## Upgrading

```bash
helm upgrade ocudu-cu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu --version 1.15.0 -f my-values.yaml
```

The chart sets `deploymentStrategy.type: Recreate` by default — the old pod
is fully terminated before the new one starts, since this is a stateful
workload that should not run overlapping old/new pods.

## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `network.hostNetwork` | bool | `false` | Enable host network mode |
| `network.ipFamilyPolicy` | string | `"PreferDualStack"` | IP family policy of the Services except the IPsec one; `""` leaves it to the cluster |
| `n2Service.enabled` | bool | `true` | Enable N2 (NGAP) Service |
| `n3Service.enabled` | bool | `true` | Enable N3 (GTP-U) Service |
| `n3Service.externalIPs` | list | `[]` | Addresses routed to the N3 Service by the surrounding network |
| `n3Service.advertisedAddress` | string | `""` | N3 address advertised to the core while the CU binds to its pod IP |
| `f1cService.enabled` | bool | `true` | Enable F1-C (F1AP) Service |
| `f1uService.enabled` | bool | `true` | Enable F1-U (GTP-U) Service; maps port 2152 to `cu_up.f1u.bind_port` (2151) |
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
| `resources` | object | 2 CPUs, 4Gi | Requests and limits; `cpu` and `memory` are required in both |
| `replicaCount` | int | `1` | Number of CU replicas |
| `serviceAccount.annotations` | object | `{}` | Annotations on the CU pod's ServiceAccount (no token is mounted, no Role is bound) |
| `startupProbe.enabled` | bool | `true` | Gate liveness/readiness until `ocu` is running |
| `priorityClassName` | string | `""` | Priority class assigned to the pod |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints for pod assignment |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `deploymentStrategy.type` | string | `"Recreate"` | Deployment update strategy |
| `o1.enable_ocudu_o1` | bool | `false` | Enable the O1 interface (NETCONF management) |
| `o1.o1Port` | int | `830` | NETCONF SSH port — image-coupled, see note below |
| `o1.netconfServer.service.type` | string | `"NodePort"` | O1 service type: `NodePort`, `LoadBalancer`, or `ClusterIP` |
| `o1.netconfServer.tls.enabled` | bool | `false` | Enable the NETCONF-over-TLS endpoint on port 6513 |
| `o1.netconfServer.tls.certSecret` | string | `""` | Secret with the server identity (`ca.crt`, `server.crt`, `server.key`); omit for auto-generated self-signed certs |
| `o1.netconfServer.tls.clientCertSecret` | string | `""` | Secret with the adapter's client identity (`ca.crt`, `client.crt`, `client.key`); required when `certSecret` is set |
| `o1.netconfServer.ssh.username` | string | `"netconf"` | NETCONF SSH user with password authentication, for clients that only implement the SSH `password` method; empty = disabled |
| `o1.netconfServer.ssh.passwordSecret` | string | `""` | Existing Secret with key `password` holding the NETCONF user's password (production) |
| `o1.netconfServer.ssh.password` | string | `"netconf"` | Dev/test cleartext password the chart renders into a Secret itself; ignored when `passwordSecret` is set |
| `o1.o1Adapter.fileLog.enabled` | bool | `false` | Persist the o1 adapter output to a log file |
| `o1.netconfServer.fileLog.enabled` | bool | `false` | Persist the netconf-server output to a timestamped log file |
| `o1.netconfServer.persistence.enabled` | bool | `true` | Keep the running config set over NETCONF across pod restarts in a PersistentVolumeClaim; every helm upgrade starts from `o1Config` again |
| `config.cu-config.yml` | string | See `values.yaml` | CU application configuration file |
| `o1Config.o1-config.xml` | string | See `values-o1.yaml` | ManagedElement template served by the netconf-server (replaces `config` in O1 mode) |

The `o1.*` and `o1Config` keys are absent from `values.yaml` — O1 is off unless
they are supplied. The defaults listed above are the ones shipped in
[`values-o1.yaml`](values-o1.yaml).

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml), or
[`values-o1.yaml`](values-o1.yaml) for the O1-enabled variant.

## Common Configuration Examples

### CNI + ClusterIP

```yaml
network:
  hostNetwork: false

config:
  cu-config.yml: |-
    cu_cp:
      amf:
        addrs: open5gs-sample-amf-ngap.default
        bind_addrs: 0.0.0.0
      f1ap:
        bind_addrs: 0.0.0.0
    cu_up:
      ngu:
        socket:
          - bind_addr: 0.0.0.0
      f1u:
        bind_port: 2151
        socket:
          - bind_addr: 0.0.0.0
```

N3 and F1-U are both GTP-U on UDP 2152. To share the pod IP, F1-U binds port 2151 in the
pod, and the F1-U Service maps port 2152 to it. Keep `cu_up.f1u.bind_port` and
`f1uService.targetPort` the same.

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

A hostPath volume ties the pod to whichever node holds that directory, so it can
only ever be rescheduled there. Treat this as a local-debugging configuration,
not a production one. Logs default to an `emptyDir` for that reason.

### Metrics with Grafana (`grafana-ocudu` chart)

The CU sends its metrics to the `grafana-ocudu` chart like the gNB does. Enable
`metricsService`, JSON metrics and the remote control server. The power metric needs
`PERFMON` in `securityContext.capabilities.add`:

```yaml
metricsService:
  enabled: true
securityContext:
  capabilities:
    add: [SYS_NICE, PERFMON]   # list replaces the default: keep SYS_NICE
config:
  cu-config.yml: |-
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

The pod becomes its own IPsec endpoint: one daemon, one IKE association per peer, and one
child association per protected interface, each on its own tunnel interface and protected
address. Every pod has its own network namespace, so two pods on the same node are still
two endpoints and the traffic between them is still encrypted.

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
  localId: cu
  peers:
    du:
      id: du
  connections:
    f1c: {protocol: sctp, local: 100.64.10.1, remote: 100.64.10.2}
    f1u: {protocol: udp, local: 100.64.30.1, remote: 100.64.30.2}
```

The DU dials the CU's headless service, `<release>-ocudu-cu-ipsec`.

**N2 and N3 are protected only with `ipsec.protectN2` and `ipsec.protectN3`**, against
core-side peers (AMF and UPF) that terminate IKEv2. Without them the policy keeps its
plaintext rules for the core and the chart claims nothing about N2 or N3.

**F1-U must not use the core's GTP-U port.** Keep `f1u.bind_port` and `peer_port` off UDP
2152 on both ends; the chart refuses to render otherwise. With `ipsec.protectN3` the policy
opens no plaintext port to the core, so F1-U may stay on 2152.

The application has to bind the protected addresses, and the chart refuses to render if it
does not. [`docs/ipsec.md`](docs/ipsec.md) has the worked example, the requirements this
places on the cluster, and the full list of what the chart refuses.

## Security Context and Capabilities

The chart defaults are otherwise restrictive — non-root pod, read-only root
filesystem, every capability dropped except `SYS_NICE`, no service account
token, no RBAC, no hostPath, no privileged container — but two settings are
deliberately not at their most restrictive value:

```yaml
securityContext:
  allowPrivilegeEscalation: true
  capabilities:
    add: [SYS_NICE]
```

`ocu` needs `SYS_NICE` to run its worker pool and its I/O thread at `SCHED_FIFO`
priority. Without it, `ocu` prints `Scheduling priority of thread "..." not changed`
and runs those threads at normal priority. Add `PERFMON` to read the RAPL power metric.

The image bakes both into the binary as permitted-only *file* capabilities
(`setcap cap_sys_nice,cap_perfmon+p`), and `ocu` starts with whichever of them the
container grants. `allowPrivilegeEscalation: false` sets `NO_NEW_PRIVS`, under which
the kernel ignores file capabilities, so the process would start without any of them.

Older OCUDU images also carry `IPC_LOCK` and set the effective bit
(`getcap /usr/local/bin/ocu` shows `=ep`). They refuse to start (`EPERM`) unless
the container grants every capability the binary declares.

With the read-only root filesystem, `ocu` writes only to `/tmp`, `/run/ocudu`
and `persistence.mountPath`, which are volumes. Point logs and pcaps at
`persistence.mountPath`.

In O1 mode ([`values-o1.yaml`](values-o1.yaml)) the pod also sets the sysctl
`net.ipv4.ip_unprivileged_port_start: "0"` under `podSecurityContext`, so the
non-root netconf-server (uid 1000) can bind `o1.o1Port` (830). Kubernetes rejects
`net.*` sysctls when `network.hostNetwork: true`, so that combination is not supported.

## Surviving a Node Drain

Nothing in the chart defaults pins the pod to a node. Keep it that way if
`kubectl drain` has to work:

- leave `persistence.enabled: false`, or use a StorageClass that is not
  node-bound — both `hostPath` and a local-path style provisioner pin the pod;
- select nodes by capability label rather than `kubernetes.io/hostname`;
- `podDisruptionBudget.minAvailable: 0` (the default) permits the eviction, but
  it does not make the pod come back — rescheduling does.

## O1 / NETCONF Interface

Enable the O1 interface by setting `o1.enable_ocudu_o1: true` and using
[`values-o1.yaml`](values-o1.yaml) as a base:

```bash
helm install ocudu-cu ./ -f values-o1.yaml
```

In O1 mode the pod gains two sidecars — `ocudu-o1-adapter` and `netconf-server`.
The `config` ConfigMap is replaced by `o1Config` (an `o1-config.xml`
ManagedElement template with a `GNBCUCPFunction` and a `GNBCUUPFunction`): the
adapter renders `cu-config.yml` from the NETCONF running config into a shared
`emptyDir`, and the entrypoint waits for that file (up to `CONFIG_CREATE_TIMEOUT`,
120s) before starting `ocu`. Liveness therefore tracks the adapter's
`/config-healthy` endpoint instead of `pgrep ocu`.

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
