# ocudu-cu-up

![Production Ready](https://img.shields.io/badge/production-ready-green.svg)

A Helm chart for deploying the OCUDU 5G CU-UP (Central Unit - User Plane)

## Overview

CU-UP terminates N3 (GTP-U, toward the UPF), E1AP (toward CU-CP), and F1-U (GTP-U, toward the DU). It was split out from the combined `ocudu-cu` chart.

## Installing the Chart

```bash
helm install ocudu-cu-up oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-up --version 1.4.0
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
helm upgrade ocudu-cu-up oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu-up --version 1.4.0 -f my-values.yaml
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
| `persistence.enabled` | bool | `false` | Enable persistent storage for logs (otherwise `emptyDir`) |
| `persistence.type` | string | `"pvc"` | Storage type: `pvc` or `hostPath` |
| `replicaCount` | int | `1` | Number of CU-UP replicas |
| `serviceAccount.automountServiceAccountToken` | bool | `false` | Mount the service account token into the pod |
| `startupProbe.enabled` | bool | `true` | Gate liveness/readiness until `ocuup` is running |
| `priorityClassName` | string | `""` | Priority class assigned to the pod |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints for pod assignment |
| `rbac.create` | bool | `false` | Create RBAC Role and RoleBinding |
| `podDisruptionBudget.enabled` | bool | `true` | Enable PodDisruptionBudget |
| `deploymentStrategy.type` | string | `"Recreate"` | Deployment update strategy |
| `o1.enable_ocudu_o1` | bool | `false` | Enable the O1 interface (NETCONF management) |
| `o1.o1Port` | int | `830` | NETCONF SSH port — image-coupled, see note below |
| `o1.netconfServer.service.type` | string | `"NodePort"` | O1 service type: `NodePort`, `LoadBalancer`, or `ClusterIP` |
| `o1.netconfServer.tls.enabled` | bool | `false` | Enable the NETCONF-over-TLS endpoint on port 6513 |
| `o1.netconfServer.tls.certSecret` | string | `""` | Secret with the server identity (`ca.crt`, `server.crt`, `server.key`); omit for auto-generated self-signed certs |
| `o1.netconfServer.tls.clientCertSecret` | string | `""` | Secret with the adapter's client identity (`ca.crt`, `client.crt`, `client.key`); required when `certSecret` is set |
| `o1.o1Adapter.fileLog.enabled` | bool | `false` | Persist the o1 adapter output to a log file |
| `o1.netconfServer.fileLog.enabled` | bool | `false` | Persist the netconf-server output to a timestamped log file |
| `config.cu-up-config.yml` | string | See `values.yaml` | CU-UP application configuration file |
| `o1Config.o1-config.xml` | string | See `values-o1.yaml` | ManagedElement template served by the netconf-server (replaces `config` in O1 mode) |

The `o1.*` and `o1Config` keys are absent from `values.yaml` — O1 is off unless
they are supplied. The defaults listed above are the ones shipped in
[`values-o1.yaml`](values-o1.yaml).

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml), or
[`values-o1.yaml`](values-o1.yaml) for the O1-enabled variant.

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

A hostPath volume ties the pod to whichever node holds that directory, so it can
only ever be rescheduled there. Treat this as a local-debugging configuration,
not a production one. Logs default to an `emptyDir` for that reason.

## Security Context and Capabilities

The chart defaults are otherwise restrictive — non-root pod, every capability
dropped except the three below, no service account token, no RBAC, no hostPath,
no privileged container — but two settings are deliberately not at their most
restrictive value:

```yaml
securityContext:
  allowPrivilegeEscalation: true
  capabilities:
    add: [SYS_NICE, IPC_LOCK, PERFMON]
```

**These capabilities are functional requirements of `ocuup`**, not an artifact of
how the image is packaged: `SYS_NICE` for real-time thread priorities,
`IPC_LOCK` for locked memory, `PERFMON` for the performance and RAPL counters.
Removing them does not harden the workload, it breaks it.

They are additionally baked into the binary as *file* capabilities
(`setcap cap_sys_nice,cap_ipc_lock,cap_perfmon+ep`), which is what forces
`allowPrivilegeEscalation: true`. Two kernel rules apply:

- with the `+ep` bits set, every capability in the file's permitted set must also
  be in the container's bounding set, or `execve()` fails with `EPERM` — dropping
  any of the three from `capabilities.add` means the container never starts;
- `allowPrivilegeEscalation: false` sets `NO_NEW_PRIVS`, under which the kernel
  ignores file capabilities entirely, so the process would start without the
  privileges it needs.

`PERFMON` is on kubescape's insecure-capability list (C-0046), so the CNTI
`privilege_escalation` and `insecure_capabilities` checks fail against this chart
**by design**. Treat that as a known, accepted result for this workload rather
than something to configure away; use the test suite's exception mechanism if the
notifications need silencing.

The O1 sidecars carry their own `securityContext` values under
`o1.o1Adapter` / `o1.netconfServer` and are unaffected by the above.

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
helm install ocudu-cu-up ./ -f values-o1.yaml
```

In O1 mode the pod gains two sidecars — `ocudu-o1-adapter` and `netconf-server`.
The `config` ConfigMap is replaced by `o1Config` (an `o1-config.xml`
ManagedElement template with a `GNBCUUPFunction`): the adapter renders
`cu-up-config.yml` from the NETCONF running config into a shared `emptyDir`, and
the entrypoint waits for that file (up to `CONFIG_CREATE_TIMEOUT`, 30s) before
starting `ocuup`. Liveness therefore tracks the adapter's `/config-healthy`
endpoint instead of `pgrep ocuup`.

The NETCONF server always listens on SSH (`o1.o1Port`, 830 by default), exposed
by `service-o1.yaml` as a NodePort. TLS (port 6513) is optional.

### Ports are coupled to the container images

`o1.o1Port` (830), `o1.healthcheckPort` (5000) and the TLS port (6513, hardcoded
in the templates) are **not freely configurable**, despite two of them being
values. Neither sidecar is passed a port flag: the netconf-server's listen ports
and the adapter's HTTP port are built into their images, and the chart values
only tell the *other* side of each pair where to connect.

Changing `o1.o1Port` therefore moves the Service, the `containerPort` and the
adapter's `--netconf_port`, while the server keeps listening on its built-in
port. The adapter cannot connect, `/config-healthy` never returns 200, and the
pod dies on `CONFIG_CREATE_TIMEOUT` — with nothing in the logs pointing at the
port. Changing `o1.healthcheckPort` aims the liveness probe and the postStart
hook at a closed port instead.

Treat all three as fixed unless you are also changing
`o1.o1Adapter.image` / `o1.netconfServer.image` to images that listen elsewhere.
`o1.netconfServer.tls.tlsNodePort` *is* genuinely configurable — it is the
external NodePort, not the port inside the pod.

### Enabling TLS

```yaml
o1:
  enable_ocudu_o1: true
  netconfServer:
    tls:
      enabled: true
      certSecret: ""  # see below
```

The o1 adapter connects to the netconf-server over **mutual TLS**, so two
identities are involved: the server's (used on port 6513) and the adapter's
client identity (its cert CN maps to the NETCONF username via `cert-to-name`).

**Option 1 — Auto-generated self-signed certs (dev/test).** Leave both
`certSecret` and `clientCertSecret` empty. The netconf-server generates a
self-signed CA + server cert + client cert at startup into a shared `emptyDir`;
the adapter reads its client cert back from it. No secrets to manage.

**Option 2 — Operator-provided certs (production).** Provide **two** secrets, so
neither container holds the other's private key. The server secret is mounted
read-only at `/etc/netconf-tls`, the client secret at `/etc/netconf-tls-client`.

```bash
# server identity
kubectl create secret generic netconf-tls-certs -n <namespace> \
  --from-file=ca.crt=./ca.crt \
  --from-file=server.crt=./server.crt \
  --from-file=server.key=./server.key

# client identity (adapter). Its client.key is a privileged credential — restrict RBAC and rotate.
kubectl create secret generic netconf-tls-client-certs -n <namespace> \
  --from-file=ca.crt=./ca.crt \
  --from-file=client.crt=./client.crt \
  --from-file=client.key=./client.key
```

Then reference both in values:

```yaml
o1:
  netconfServer:
    tls:
      enabled: true
      certSecret: netconf-tls-certs
      clientCertSecret: netconf-tls-client-certs
```

`clientCertSecret` is required whenever `certSecret` is set — rendering fails
with a clear message otherwise. The server uses its secret as-is without
generating new certs.

### Persistent sidecar logs

Both sidecars can tee their output to a file under `persistence.mountPath` (the
same volume as the `ocuup` logs) while still reaching pod stdout, so
`kubectl logs` keeps working. All three containers mount the shared `ocudu-logs`
volume. The files are appended to, are not rotated, and only survive pod
restarts when `persistence.enabled` is true.

```yaml
o1:
  o1Adapter:
    fileLog:
      enabled: true
      filename: o1-adapter.log
  netconfServer:
    fileLog:
      enabled: true
      filename: netconf.log
```

The adapter timestamps its own lines, so they are copied verbatim — including
the ANSI colour codes around the log level, so read that file with `less -R`.
The netconf-server emits no timestamps, so its lines are prefixed with
`[YYYY-MM-DD HH:MM:SS]` on the way to the file.

## Support

- **Documentation**: [OCUDU Docs](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Issues**: [GitLab Issues](https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/-/issues)

## License

BSD-3-Clause-Open-MPI - See LICENSE file for details
