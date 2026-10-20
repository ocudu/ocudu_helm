# Changelog

## 1.15.0 (2026-10-26)

### Added

- Optional NETCONF SSH user with password authentication for clients that
  only implement the SSH `password` method.
  `o1.netconfServer.ssh.{username,passwordSecret,password}` keeps an empty
  username for the old behavior; the password lives only in a Secret — an
  operator-provided one via `passwordSecret`, or a chart-created one from
  `password` (dev/test) — and the chart maps
  `NETCONF_SSH_USERNAME`/`NETCONF_SSH_PASSWORD` onto the netconf-server
  container for the image's `setup_ssh_user.sh` to create the user and its
  NACM grant. Requires a netconf-server image with the env-var support (the
  `values-o1.yaml` pin has it); see `docs/o1.md` in the ocudu-gnb chart.

### Changed

- `values-o1.yaml`: bump the netconf-server image to `20261014_39618f9e`,
  the nightly with the `setup_ssh_user.sh` env-var support

## 1.14.1 (2026-10-22)

### Fixed

- `values-o1.yaml`: the non-root netconf-server could not bind port 830; set the pod sysctl `net.ipv4.ip_unprivileged_port_start` to `0`

## 1.14.0 (2026-10-20)

### Changed

- The CU pod always runs as the chart's own ServiceAccount, named after the release, with **no token mounted** (`automountServiceAccountToken: false` on the ServiceAccount and the pod spec) and **no Role or RoleBinding**: nothing in the pod uses the Kubernetes API (CNTi `service_account_mapping` and `dedicated_service_account`, CIS 5.1.5 and 5.1.6)

### Removed

- `serviceAccount.create`, `serviceAccount.name` and `serviceAccount.automountServiceAccountToken`, and the whole `rbac` block (`rbac.create`, `rbac.extraRules`) with the Role and RoleBinding templates: the Role granted `configmaps` and `pods` access that nothing in the pod used, and `values-o1.yaml` created it without mounting the token to use it. `serviceAccount.annotations` stays. A sidecar that needs the API is a chart change, not a value.

## 1.13.0 (2026-10-19)

### Added

- `ipsec.allowXnuOnCorePort`: the companion to `allowF1uOnCorePort` for Xn-U, which defaults to the same GTP-U port the policy has to open for the core. The chart now refuses to render while a protected Xn-U sits on that port, because the rule opened for the core would also permit plaintext Xn-U to the peer's pod address. Xn-U's port is configurable, so move it on both ends rather than open this
- `ipsec`: Xn-C and Xn-U can now be protected, against another gNB running the same sidecar. Add the peer and a connection for each, and point `cu_cp.xnap.gateways[].bind_addrs`, `.connections[].peer_addrs` and `cu_up.xnu.socket[].bind_addr` at the protected addresses. Xn-U also has to leave the core's GTP-U port, on both ends. One side carries the peer's `address` and starts the connection; the other leaves it out and sets `cu_cp.xnap.no_connection_init`, so neither layer dials from that end. The peer is allowed through with `networkPolicy.ingress.xn` and `networkPolicy.egress.xn`, both off by default and both opening the tunnel only. See `docs/ipsec.md`

### Fixed

- `ipsec`: the render-time address check read only addresses written beside their key, so a protected section that listed its bind addresses one per line — the form SCTP multi-homing uses — could name a wildcard or a pod address alongside the protected one and still render. A value written as a list item is now checked the same way as one written inline
- `ipsec`: the core-port check treated a user-plane section the application config does not carry as one left on the default port, so protecting only the control plane was refused with a message about an interface that was not configured at all. A section that is absent is now left alone
- `ipsec.image.tag` defaults to `6.0.4_1.0.0`; the previous default, `6.0.4`, was never published

## 1.12.0 (2026-10-16)

### Added

- `ipsec`: optional strongSwan sidecar protecting F1-C and F1-U with IKEv2 and tunnel-mode ESP. One daemon per pod, one IKE association per peer under `ipsec.peers`, and one child association per interface under `ipsec.connections`, each on its own XFRM interface and protected address, so the CU and the DU stay separate tunnel endpoints even on one node. Off by default. It brings a headless service for the peer to resolve, a NetworkPolicy that allows the peer the tunnel and nothing else, render-time guards that refuse any configuration that would run unprotected, and an optional cert-manager `Certificate`. Requires Kubernetes 1.29 or newer, `network.hostNetwork: false`, and a node whose kernel provides XFRM interfaces and ESP to an unprivileged container. See `docs/ipsec.md`

- `ipsec.connections.<name>.protocol`: narrow a tunnel to the protocol that interface speaks, `sctp` for F1-C and E1 or `udp` for F1-U. Traffic between the two protected addresses that is not that protocol then matches no policy and is dropped, instead of being encrypted and delivered. Optional; left out, the tunnel admits any protocol between those addresses, which also admits ICMP and so path-MTU discovery
- `ipsec.connections.<name>.ifName` and `.ifId` are now derived from the connection name, so a protected interface is four keys: the peer that carries it, the protocol, and the two protected addresses. Both are still settable where a specific value is required
- `ipsec.ike.replayWindow`: how far out of order a packet may arrive and still be accepted, defaulting to 32. Previously unset, so the width was whatever the daemon chose rather than a number the chart chose. It applies to the whole daemon, so a per-connection value is refused; a width of 0 is refused because it switches replay protection off; and a width above 32 is refused unless `espProposal` carries `esn`, because without it the kernel falls back to a window of 1
- `ipsec.ike.retransmitTimeout` and `ipsec.ike.retransmitTries`: how quickly a peer that has stopped answering is given up on, defaulting to 2 seconds and 3 tries. This pair, not `dpdDelay`, governs it — the daemon's defaults retry for about 165 seconds, and for all of that time this side keeps encrypting into an association the peer no longer has
- `ipsec.startupProbe`: hold the application container until the sidecar's daemon has loaded every interface it was given and the tunnel interfaces exist. On by default. It does not wait for a tunnel to come up, which a side waiting to be dialled could never satisfy
- `ipsec.logLevel`: daemon verbosity, for following a negotiation that will not complete
- `ipsec.ikeOnNatTPortOnly`: carry IKE on UDP 4500 only. Nothing binds a privileged port, so the sidecar runs without `NET_BIND_SERVICE` and the network policy opens one port instead of two. Off by default, and both ends have to set it
- `ipsec.credentialReload`: the sidecar watches its mounted secret and picks up a renewed certificate on its own, loading the new credentials in place of the old ones and closing the IKE association so the next traffic authenticates with the new certificate. No pod restart. On by default
- `ipsec.allowF1uOnCorePort`: the chart now refuses to render when the application leaves F1-U on the core's GTP-U port, because the policy rule that has to stay open for the core would also permit plaintext F1-U to the peer's pod address. Set F1-U to another port on both ends, or set this to allow it where there is no core
- `docs/ipsec.md` now covers choosing the certificate authority for these tunnels. A peer is accepted on two things only — its certificate chains to the authority in `ca.crt`, and its identity matches the `id` configured for it — so an authority dedicated to these tunnels is safer than a general-purpose one that also serves other systems
- `ipsec.resources` and `docs/ipsec.md` now say that a node pinning CPUs with the kubelet's `static` policy needs requests equal to limits on the sidecar. A container is given exclusive CPUs only while the whole pod is Guaranteed, so a sidecar with unequal requests and limits drops the pod to Burstable and takes the application container's pinning with it

### Changed

- Default `resources` to 2 CPUs and 4Gi in both requests and limits; OCUDU allocates a 2 GiB buffer pool at startup

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
