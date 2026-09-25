# Changelog

## 1.12.0 (2026-10-16)

### Added

- `ipsec`: optional strongSwan sidecar protecting F1-C and F1-U with IKEv2 and tunnel-mode ESP. One daemon per pod, one IKE association per peer under `ipsec.peers`, and one child association per interface under `ipsec.connections`, each on its own XFRM interface and protected address, so the CU and the DU stay separate tunnel endpoints even on one node. Off by default. It brings a headless service for the peer to resolve, a NetworkPolicy that allows the peer the tunnel and nothing else, render-time guards that refuse any configuration that would run unprotected, and an optional cert-manager `Certificate`. Requires Kubernetes 1.29 or newer, `network.hostNetwork: false`, and a node whose kernel provides XFRM interfaces and ESP to an unprivileged container. See `docs/ipsec.md`

- `ipsec.connections.<name>.protocol`: narrow a tunnel to the protocol that interface speaks, `sctp` for F1-C and E1 or `udp` for F1-U. Traffic between the two protected addresses that is not that protocol then matches no policy and is dropped, instead of being encrypted and delivered. Optional; left out, the tunnel admits any protocol between those addresses, which also admits ICMP and so path-MTU discovery
- `ipsec.connections.<name>.ifName` and `.ifId` are now derived from the connection name, so a protected interface is four keys: the peer that carries it, the protocol, and the two protected addresses. Both are still settable where a specific value is required
- `ipsec.ikeOnNatTPortOnly`: carry IKE on UDP 4500 only. Nothing binds a privileged port, so the sidecar runs without `NET_BIND_SERVICE` and the network policy opens one port instead of two. Off by default, and both ends have to set it
- `ipsec.credentialReload`: the sidecar watches its mounted secret and picks up a renewed certificate on its own, loading the new credentials in place of the old ones and closing the IKE association so the next traffic authenticates with the new certificate. No pod restart. On by default
- `ipsec.allowF1uOnCorePort`: the chart now refuses to render when the application leaves F1-U on the core's GTP-U port, because the policy rule that has to stay open for the core would also permit plaintext F1-U to the peer's pod address. Set F1-U to another port on both ends, or set this to allow it where there is no core

### Fixed

- `ipsec.readinessProbe`: the probe reported not ready for any interface that had no traffic yet, which is the normal state of F1-U with no user attached, so a pod with it enabled never became ready. It now reports ready when the IKE association is up and every interface has a child association or the policy that stands in for one
- `dnsPolicy: ClusterFirstWithHostNet` was set twice in the pod spec, so every pod got the host-network policy whether or not it used host networking
- `checksum/config` was skipped in O1 mode, so a change to the entrypoint script did not roll an O1 pod

## 1.11.0 (2026-10-11)

### Changed

- Drop `IPC_LOCK` from the default `securityContext` in `values.yaml` and `values-o1.yaml`; `ocu` uses no DPDK. Needs an image with permitted-only file capabilities (`getcap` shows `=p`); older images fail with `EPERM` unless `IPC_LOCK` is added back
- `values.yaml`, `values-o1.yaml`: describe the file capabilities; add `PERFMON` to read the RAPL power metric

## 1.10.1 (2026-10-09)

### Changed

- Set `appVersion` to the OCUDU release `26.10`

## 1.10.0 (2026-10-09)

### Changed

- **Breaking:** `resources.requests` and `resources.limits` must set `cpu` and `memory` (rendering fails otherwise)
- Remove `metricsService.powercap.enabled`; the `ocu` binary does not use `PERFMON`
- `values-o1.yaml`: drop `PERFMON`, matching `values.yaml`
- `values-o1.yaml`: update the O1 adapter and netconf-server images and adapt `o1Config` to the current netconf YANG models

### Fixed

- Set the default image tag to `ubuntu-24.04-avx2-20261007_2e9f5671`; the appVersion `26.04` is not a published tag
- O1 adapter no longer exits when `o1.netconfServer.ssh.hostKeySecret` is set

## 1.9.3 (2026-10-07)

### Fixed

- The entrypoint no longer takes the log directory from a `filename:` value without a directory part, such as `stdout`, `stderr` or a bare file name. Such a value made it create the timestamped log directory in the working directory, `/`, which fails when the container runs as a non-root user and `persistence.preserveOldLogs` is enabled. The first `filename:` value with a directory part is used instead, and if there is none the log path update is skipped (#73)

## 1.9.2 (2026-10-06)

### Fixed

- N3 can use an address reachable by an external UPF while the CU stays on the
  pod network. `n3Service.externalIPs` publishes UDP/2152 on that address and
  `n3Service.advertisedAddress` makes the application signal it to the core while
  continuing to bind the socket to its pod IP. The Service applies
  `externalTrafficPolicy` to external IPs as well as LoadBalancers and NodePorts.

## 1.9.1 (2026-09-30)

### Fixed

- With O1 enabled, a configuration change that the O1 adapter cannot apply at runtime restarts the CU inside the running container. The entrypoint replaced itself with the CU, so every such change ended the container and the kubelet's restart backoff delayed the CU longer each time. With O1 the CU now runs as a child of the entrypoint; without O1 it still replaces it
- An O1 pod starts without restarting the CU container. Its postStart hook waited for the O1 adapter, which the kubelet only starts once the hook has finished, so the hook failed on every first start; the entrypoint now notifies the adapter itself. The entrypoint also waits up to 120 s instead of 30 s for the O1 configuration, since the NETCONF server alone can take 30 s to load its models

## 1.9.0 (2026-09-09)

### Added

- `o1.netconfServer.ssh.hostKeySecret`: pin the netconf-server's SSH host key from a secret (`ssh_host_{ed25519,ecdsa,rsa}_key` plus the matching `known_hosts`, which the o1 adapter verifies against) instead of the key generated in its image. Empty by default

## 1.8.1 (2026-09-08)

### Added

- `initCommand` configures the init process used as container PID 1 and defaults to `catatonit`, matching the gNB and DU charts

## 1.8.0 (2026-08-06)

### Added

- `o1.o1Adapter.fileLog.{enabled,filename}`: optionally persist the o1 adapter container's stdout/stderr to a log file under `persistence.mountPath`. When enabled the container command is wrapped in a shell that tees the stream to the file (mounting the shared `ocudu-logs` volume, alongside the ocu and netconf-server logs) while still forwarding it to pod stdout so `kubectl logs` keeps working. The adapter timestamps its own lines, so they are copied verbatim

## 1.7.0 (2026-08-05)

### Added

- `replicaCount` (default `1`): the Deployment previously had no `replicas` field at all
- `topologySpreadConstraints` and `priorityClassName` values, for keeping the CU schedulable across a node drain
- `startupProbe` (`enabled`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`; `pgrep ocu`, 180s budget by default) which gates the liveness and readiness probes in both plain and O1 mode
- `serviceAccount.automountServiceAccountToken` (default `false`), applied to both the ServiceAccount and the pod spec — nothing in the pod uses the Kubernetes API (CNTI `service_account_mapping`, kubescape C-0034)
- `ocudu-cu.mainImage` template helper

### Changed

- **`rbac.create` now defaults to `false`** — the Role granted `configmaps get/list/watch` and `pods get`, which no container in the pod ever used
- **`persistence.type` now defaults to `pvc`** — `hostPath` is opt-in for local debugging, since it fails the CNTI `hostpath_mounts` essential check and pins the pod to one node, blocking `node_drain`. Note that a node-bound StorageClass (e.g. `local-path`) pins the pod just as hostPath does. `persistence.enabled` was already `false`
- `readinessProbe.initialDelaySeconds` 15 → `0`, with the new `startupProbe` taking over slow-start tolerance — removes ~15s of dead time from every start (CNTI `reasonable_startup_time`). `livenessProbe` is unchanged: the startup probe already gates it, and leaving `initialDelaySeconds` at 90 preserves the original tolerance if the startup probe is ever disabled
- `readinessProbe.failureThreshold` 30 → `6` and `timeoutSeconds` 1 → `3`, so a dead process leaves the Services in ~30s rather than ~150s, without a slow `exec` probe under node pressure flapping the endpoints of a single-replica Deployment

### Fixed

- `image.tag: ""` (the shipped default) rendered the invalid reference `registry.gitlab.com/ocudu/ocudu/images/cu:` — the tag now falls back to the chart `appVersion`, as `values.yaml` already documented with `@default -- Chart appVersion`
- `values.yaml`: the liveness and readiness probe comments described them as "DU" probes in the CU chart

## 1.6.0 (2026-07-30)

### Added

- `emptyDir` volume mounted at `/run/ocudu` (`OCUDU_WORK_DIR`) for the runtime config, decoupled from `persistence.mountPath`. The `*-config-rendered.yml` snapshot stays under `OCUDU_LOG_DIR` so it survives pod restarts
- `checksum/config` pod annotation (when O1 is disabled) to trigger a rollout when the ConfigMap changes

## 1.5.0 (2026-07-09)

### Added

- `o1.netconfServer.fileLog.{enabled,filename}`: optionally persist the netconf-server container's stdout/stderr to a timestamped log file under `persistence.mountPath`. When enabled, the container command is wrapped in a shell that prefixes each line with a `[YYYY-MM-DD HH:MM:SS]` timestamp and tees it to the file (mounting the shared `ocudu-logs` volume) while still forwarding output to pod stdout so `kubectl logs` keeps working

## 1.4.0 (2026-07-06)

### Added

- `o1.netconfServer.tls.clientCertSecret`: separate TLS client identity for the o1 adapter, which now connects to the netconf-server over mutual TLS (auto-generated via `emptyDir` in dev/test)

### Changed

- **Breaking:** `certSecret` now requires a companion `clientCertSecret` (rendering fails otherwise)
- bump `o1.o1Adapter.image.tag` to `20260706_bd8b634b` for NETCONF-over-TLS client support

## 1.3.1 (2026-06-29)

### Added

- O1/NETCONF support gated on `o1.enable_ocudu_o1`: adds `ocudu-o1-adapter` and `netconf-server` sidecars, a NETCONF service (`service-o1.yaml`, NodePort/LoadBalancer with optional TLS on 6513), the `o1Config` ConfigMap, an O1-mode liveness probe, and the `o1.*` configuration values
- entrypoint.sh: wait for the O1-generated config before launching `ocu` (`ENABLE_OCUDU_O1`/`CONFIG_CREATE_TIMEOUT`)
- `values-o1.yaml`: example values preset with O1 enabled
- deployment.yaml: `PERFMON` capability on the CU container for powercap RAPL energy reads (`metricsService.powercap.enabled`)

### Changed

- values.yaml: default image repository changed from `ocudu_nightly_avx512` to `images/cu`
- deployment.yaml: set `dnsPolicy: ClusterFirstWithHostNet` on the pod spec
## 1.2.2 (2026-07-01)

### Added

- `deploymentStrategy` value (defaults to `Recreate`) to control the Deployment update strategy

## 1.2.1 (2026-06-02)

### Added

- `emptyDir` volume mounted at `persistence.mountPath` when `persistence.enabled=false` — ensures log directory is always writable without requiring a hostPath or PVC

### Changed

- deployment.yaml: switch container command to `tini --` as PID 1 for zombie reaping and signal forwarding (fixes CNTi `specialized_init_system` and `zombie_handled` tests)
- values.yaml: document that `image.tag` must be quoted in values files to avoid YAML float parsing

## 1.2.0 (2026-06-01)

### Changed

- Rename default log/pcap paths from `/var/log/srs` to `/var/log/ocudu` in entrypoint.sh and values.yaml

## 1.1.0 (2026-06-01)

### Added

- Non-root `podSecurityContext` (uid/gid 1000) and minimum-privilege `securityContext` (SYS_NICE, IPC_LOCK)
- `network.hostNetwork` toggle with conditional `dnsPolicy`
- tini as PID 1 for signal forwarding and zombie reaping
- Liveness and readiness probes (`pgrep ocu`)
- `POD_IP`, `HOSTNETWORK`, `OCUDU_LOG_DIR` env vars in deployment
- N2/N3 service (`service.yaml`) — SCTP:38412 and UDP:2152
- Metrics service (`service-metrics.yaml`) — TCP:8001
- Network policy (`networkpolicy.yaml`) — N2/N3 + F1-C/F1-U + monitoring
- entrypoint.sh: IP override injection (POD_IP into `cu_cp.amf.bind_addr` and `cu_up.ngu.socket[].bind_addr`; `ext_addr` when `USE_EXT_CORE=true`)
- entrypoint.sh: in-process restart loop with SIGTERM forwarding to ocu
- entrypoint.sh: rendered config snapshot to `${OCUDU_LOG_DIR}/cu-config-rendered.yml`
- NOTES.txt

### Changed

- Replace all SRS-specific references with OCUDU equivalents: `entrypoint-srscu.sh` → `entrypoint-ocudu-cu.sh`, `entrypoint-volume-srscu` → `entrypoint-volume-ocudu-cu`, `srs-logs` → `ocudu-logs`, `SRS_LOG_DIR` → `OCUDU_LOG_DIR`, `/var/log/srs` → `/var/log/ocudu`
- `persistence.mountPath` default from `/tmp` to `/var/log/srs`
- Default config log/pcap paths updated from `/tmp` to `/var/log/srs`

## 1.0.0 (2026-04-09)

### Added
- Initial version of the OCUDU CU Helm chart
