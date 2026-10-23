# Changelog

## Unreleased

### Added

- `ipsec.protectN2`: carry N2 in a tunnel as well, to a core-side peer (AMF) that runs its own IKEv2 endpoint. Add the AMF as a peer with a connection for N2, and point `cu_cp.amf.addrs` and `cu_cp.amf.bind_addrs` at its protected addresses. The `amf` section is then checked like the other protected sections (no wildcard, no address outside `ipsec.connections`, a bind address required), and so is every entry of `extra_amfs`. The entrypoint stops prepending the pod IP as the N2 bind address, the network policy allows the core the tunnel instead of plaintext SCTP 38412, and `n2Service.enabled` is refused, as is `ipsec.protectN2` without `ipsec.enabled`. Off by default. See `docs/ipsec.md`, which now has a worked example of both sides
- With IPsec on, a protected section that sets `bind_interface` to anything but `auto` is refused: the socket would be pinned to that device and its traffic would leave outside the tunnel
- The chart pipeline runs the essential tests of the CNTi Test Suite against the chart without a core network on a kind cluster on a runner with the SCTP kernel module, through the suite's GitLab CI/CD component. The README shows the result as a badge; the values the job uses live under `.gitlab/cnti/ocudu-cu-cp/`

### Changed

- Default image tag `ubuntu-24.04-avx2-latest` with `image.pullPolicy: Always`; it moves to each nightly build, while dated tags are pruned from the registry

## 1.12.0 (2026-10-26)

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

## 1.11.1 (2026-10-22)

### Fixed

- `values-o1.yaml`: the non-root netconf-server could not bind port 830; set the pod sysctl `net.ipv4.ip_unprivileged_port_start` to `0`

## 1.11.0 (2026-10-20)

### Changed

- The CU-CP pod always runs as the chart's own ServiceAccount, named after the release, with **no token mounted** (`automountServiceAccountToken: false` on the ServiceAccount and the pod spec) and **no Role or RoleBinding**: nothing in the pod uses the Kubernetes API (CNTi `service_account_mapping` and `dedicated_service_account`, CIS 5.1.5 and 5.1.6)

### Removed

- `serviceAccount.create`, `serviceAccount.name` and `serviceAccount.automountServiceAccountToken`, and the whole `rbac` block (`rbac.create`, `rbac.extraRules`) with the Role and RoleBinding templates: the Role granted `configmaps` and `pods` access that nothing in the pod used, and `values-o1.yaml` created it without mounting the token to use it. `serviceAccount.annotations` stays. A sidecar that needs the API is a chart change, not a value.

## 1.10.0 (2026-10-19)

### Added

- `ipsec`: Xn-C can now be protected, against another gNB running the same sidecar. Add the peer and a connection for it, and point `cu_cp.xnap.gateways[].bind_addrs` and `.connections[].peer_addrs` at the protected addresses. One side carries the peer's `address` and starts the connection; the other leaves it out and sets `cu_cp.xnap.no_connection_init`, so neither layer dials from that end. The peer is allowed through with `networkPolicy.ingress.xn` and `networkPolicy.egress.xn`, both off by default and both opening the tunnel only. See `docs/ipsec.md`

### Fixed

- `ipsec`: the render-time address check read only addresses written beside their key, so a protected section that listed its bind addresses one per line — the form SCTP multi-homing uses — could name a wildcard or a pod address alongside the protected one and still render. A value written as a list item is now checked the same way as one written inline
- `ipsec.image.tag` defaults to `6.0.4_1.0.0`; the previous default, `6.0.4`, was never published

## 1.9.0 (2026-10-16)

### Added

- `ipsec`: optional strongSwan sidecar protecting F1-C and E1 with IKEv2 and tunnel-mode ESP. One daemon per pod, one IKE association per peer under `ipsec.peers`, and one child association per interface under `ipsec.connections`, each on its own XFRM interface and protected address, so the CU-CP, the CU-UP and the DU stay separate tunnel endpoints even on one node. Off by default. It brings a headless service for the peers to resolve, a NetworkPolicy that allows each peer the tunnel and nothing else, render-time guards that refuse any configuration that would run unprotected, and an optional cert-manager `Certificate`. Requires Kubernetes 1.29 or newer, `network.hostNetwork: false`, and a node whose kernel provides XFRM interfaces and ESP to an unprivileged container. N2 is not protected: it needs a peer on the core side that terminates IKEv2. See `docs/ipsec.md`

- `ipsec.connections.<name>.ifName` and `.ifId` are now derived from the connection name, so a protected interface is four keys: the peer that carries it, the protocol, and the two protected addresses. Both are still settable where a specific value is required
- `networkPolicy.egress.dnsTo`: where the cluster DNS lives. The default names the cluster DNS pods, which is what this chart already did. Set it to `[]` to allow port 53 to any destination instead — needed on a CNI that applies policy to the service address rather than to the pod behind it, where the narrow rule matches nothing and every name lookup fails
- `ipsec.ike.replayWindow`: how far out of order a packet may arrive and still be accepted, defaulting to 32. Previously unset, so the width was whatever the daemon chose rather than a number the chart chose. It applies to the whole daemon, so a per-connection value is refused; a width of 0 is refused because it switches replay protection off; and a width above 32 is refused unless `espProposal` carries `esn`, because without it the kernel falls back to a window of 1
- `ipsec.ike.retransmitTimeout` and `ipsec.ike.retransmitTries`: how quickly a peer that has stopped answering is given up on, defaulting to 2 seconds and 3 tries. This pair, not `dpdDelay`, governs it — the daemon's defaults retry for about 165 seconds, and for all of that time this side keeps encrypting into an association the peer no longer has
- `ipsec.startupProbe`: hold the application container until the sidecar's daemon has loaded every interface it was given and the tunnel interfaces exist. On by default. It does not wait for a tunnel to come up, which a side waiting to be dialled could never satisfy
- `ipsec.logLevel`: daemon verbosity, for following a negotiation that will not complete
- `ipsec.ikeOnNatTPortOnly`: carry IKE on UDP 4500 only. Nothing binds a privileged port, so the sidecar runs without `NET_BIND_SERVICE` and the network policy opens one port instead of two. Off by default, and both ends have to set it
- `ipsec.credentialReload`: the sidecar watches its mounted secret and picks up a renewed certificate on its own, loading the new credentials in place of the old ones and closing the IKE association so the next traffic authenticates with the new certificate. No pod restart. On by default
- `ipsec.connections.<name>.protocol`: narrow a tunnel to the protocol that interface speaks, `sctp` for F1-C and E1 or `udp` for F1-U. Traffic between the two protected addresses that is not that protocol then matches no policy and is dropped, instead of being encrypted and delivered. Optional; left out, the tunnel admits any protocol between those addresses, which also admits ICMP and so path-MTU discovery
- `docs/ipsec.md` now covers choosing the certificate authority for these tunnels. A peer is accepted on two things only — its certificate chains to the authority in `ca.crt`, and its identity matches the `id` configured for it — so an authority dedicated to these tunnels is safer than a general-purpose one that also serves other systems
- `ipsec.resources` and `docs/ipsec.md` now say that a node pinning CPUs with the kubelet's `static` policy needs requests equal to limits on the sidecar. A container is given exclusive CPUs only while the whole pod is Guaranteed, so a sidecar with unequal requests and limits drops the pod to Burstable and takes the application container's pinning with it

### Changed

- Default `resources` to 1 CPU and 4Gi in both requests and limits; OCUDU allocates a 2 GiB buffer pool at startup

## 1.8.0 (2026-10-11)

### Changed

- Drop `IPC_LOCK` from the default `securityContext` in `values.yaml` and `values-o1.yaml`; `ocucp` uses no DPDK. Needs an image with permitted-only file capabilities (`getcap` shows `=p`); older images fail with `EPERM` unless `IPC_LOCK` is added back
- README and `values.yaml`: describe the permitted-only file capabilities; remove `PERFMON` to pass the CNTI `insecure_capabilities` check

## 1.7.1 (2026-10-09)

### Changed

- Set `appVersion` to the OCUDU release `26.10`

## 1.7.0 (2026-10-09)

### Changed

- **Breaking:** `resources.requests` and `resources.limits` must set `cpu` and `memory` (rendering fails otherwise)
- Remove the unused `metricsService.powercap.enabled`
- README and `values.yaml`: correct which capabilities `ocucp` needs
- `values-o1.yaml`: update the O1 adapter and netconf-server images and adapt `o1Config` to the current netconf YANG models

### Fixed

- Set the default image tag to `ubuntu-24.04-avx2-20261007_2e9f5671`; the appVersion `26.04` is not a published tag
- O1 adapter no longer exits when `o1.netconfServer.ssh.hostKeySecret` is set

## 1.6.2 (2026-10-07)

### Fixed

- The entrypoint no longer takes the log directory from a `filename:` value without a directory part, such as `stdout`, `stderr` or a bare file name. Such a value made it create the timestamped log directory in the working directory, `/`, which fails when the container runs as a non-root user and `persistence.preserveOldLogs` is enabled. The first `filename:` value with a directory part is used instead, and if there is none the log path update is skipped (#73)

## 1.6.1 (2026-09-30)

### Fixed

- With O1 enabled, a configuration change that the O1 adapter cannot apply at runtime restarts the CU-CP inside the running container. The entrypoint replaced itself with the CU-CP, so every such change ended the container and the kubelet's restart backoff delayed the CU-CP longer each time. With O1 the CU-CP now runs as a child of the entrypoint; without O1 it still replaces it
- An O1 pod starts without restarting the CU-CP container. Its postStart hook waited for the O1 adapter, which the kubelet only starts once the hook has finished, so the hook failed on every first start; the entrypoint now notifies the adapter itself. The entrypoint also waits up to 120 s instead of 30 s for the O1 configuration, since the NETCONF server alone can take 30 s to load its models

## 1.6.0 (2026-09-09)

### Added

- `o1.netconfServer.ssh.hostKeySecret`: pin the netconf-server's SSH host key from a secret (`ssh_host_{ed25519,ecdsa,rsa}_key` plus the matching `known_hosts`, which the o1 adapter verifies against) instead of the key generated in its image. Empty by default

## 1.5.1 (2026-09-09)

### Added

- `initCommand` configures the init process used as container PID 1 and defaults to `catatonit`, matching the gNB, CU and DU charts

## 1.5.0 (2026-08-06)

### Added

- `o1.o1Adapter.fileLog.{enabled,filename}`: optionally persist the o1 adapter container's stdout/stderr to a log file under `persistence.mountPath`. When enabled the container command is wrapped in a shell that tees the stream to the file (mounting the shared `ocudu-logs` volume, alongside the ocucp and netconf-server logs) while still forwarding it to pod stdout so `kubectl logs` keeps working. The adapter timestamps its own lines, so they are copied verbatim

## 1.4.0 (2026-08-05)

### Added

- `replicaCount` (default `1`): the Deployment previously had no `replicas` field at all
- `topologySpreadConstraints` and `priorityClassName` values, for keeping the CU-CP schedulable across a node drain
- `startupProbe` (`enabled`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`; `pgrep ocucp`, 180s budget by default) which gates the liveness and readiness probes in both plain and O1 mode
- `serviceAccount.automountServiceAccountToken` (default `false`), applied to both the ServiceAccount and the pod spec — nothing in the pod uses the Kubernetes API (CNTI `service_account_mapping`, kubescape C-0034)
- `ocudu-cu-cp.mainImage` template helper

### Changed

- **`persistence.enabled` now defaults to `false`** — logs go to an `emptyDir`, leaving the pod reschedulable onto any node. `hostPath` mounts fail the CNTI `hostpath_mounts` essential check and pin the pod to one node, blocking `node_drain`
- **`persistence.type` now defaults to `pvc`** — `hostPath` is opt-in for local debugging. Note that a node-bound StorageClass (e.g. `local-path`) pins the pod just as hostPath does
- **`rbac.create` now defaults to `false`** — the Role granted `configmaps get/list/watch` and `pods get`, which no container in the pod ever used
- `readinessProbe.initialDelaySeconds` 15 → `0`, with the new `startupProbe` taking over slow-start tolerance — removes ~15s of dead time from every start (CNTI `reasonable_startup_time`). `livenessProbe.initialDelaySeconds` is intentionally left at 90: the startup probe already gates it, and keeping it preserves the original tolerance if the startup probe is ever disabled
- `readinessProbe.failureThreshold` 30 → `6` and `timeoutSeconds` 1 → `3`, so a dead process leaves the Services in ~30s rather than ~150s, without a slow `exec` probe under node pressure flapping the endpoints of a single-replica Deployment

### Fixed

- `image.tag: ""` (the shipped default) rendered the invalid reference `registry.gitlab.com/ocudu/ocudu/images/cu-cp:` — the tag now falls back to the chart `appVersion`, as `values.yaml` already documented with `@default -- Chart appVersion`

## 1.3.0 (2026-07-30)

### Added

- `emptyDir` volume mounted at `/run/ocudu` (`OCUDU_WORK_DIR`) for the runtime config, decoupled from `persistence.mountPath`. The `*-config-rendered.yml` snapshot stays under `OCUDU_LOG_DIR` so it survives pod restarts
- `checksum/config` pod annotation (when O1 is disabled) to trigger a rollout when the ConfigMap changes

## 1.2.0 (2026-07-29)

### Added

- O1/NETCONF support gated on `o1.enable_ocudu_o1`: adds `ocudu-o1-adapter` and `netconf-server` sidecar containers to the CU-CP pod
- `service-o1.yaml`: NETCONF service (NodePort by default, optional LoadBalancer) exposing `o1.o1Port`, plus the optional TLS port 6513
- `o1Config` ConfigMap (`o1-config.xml` ManagedElement template with `GNBCUCPFunction`) rendered to the netconf-server when O1 is enabled, selected in place of the main `config` ConfigMap
- O1-mode liveness probe via the adapter's `/config-healthy` endpoint on `o1.healthcheckPort`, plus a `postStart` hook that notifies the adapter (`/restarted`) once it is healthy
- `o1.netconfServer.tls.{enabled,certSecret,clientCertSecret,tlsNodePort}` for the NETCONF-over-TLS endpoint on port 6513; `certSecret` requires a companion `clientCertSecret` (rendering fails otherwise), otherwise self-signed certs are auto-generated via `emptyDir` in dev/test
- `o1.netconfServer.fileLog.{enabled,filename}`: optionally persist the netconf-server container's stdout/stderr to a timestamped log file under `persistence.mountPath`
- `o1.*` values: `netconfServerAddr`, `o1Port`, `healthcheckPort`, `oamIpv4Address`, `log_level`, `ws.*`, `ves.*`, `o1Adapter.{image,resources,securityContext}`, `netconfServer.{image,service,resources,securityContext}`
- entrypoint.sh: `ENABLE_OCUDU_O1`/`CONFIG_CREATE_TIMEOUT` handling — wait for the O1-generated config before launching `ocucp`, and remove it between restart iterations
- `configmap.o1.nameOverride` value and `ocudu-cu-cp.o1ConfigmapName` template helper
- `values-o1.yaml`: example values preset with O1 enabled

### Changed

- deployment.yaml: set `dnsPolicy: ClusterFirstWithHostNet` on the pod spec unconditionally (previously only when `network.hostNetwork` was enabled) so the O1 sidecars can resolve the SMO in either network mode

## 1.1.0 (2026-07-06)

### Added

- `deploymentStrategy` value (defaults to `Recreate`) to control the Deployment update strategy
- `checksum/config` pod annotation to trigger a rollout when the ConfigMap changes

### Fixed

- entrypoint.sh: exec the correct `ocucp` binary instead of the legacy combined-chart `ocu`; same fix for the `pgrep` liveness/readiness probe command
- securityContext: add `PERFMON` to the default capabilities unconditionally (the `ocucp` binary has `cap_perfmon` baked in as a file capability and cannot exec without it) — previously only added when `metricsService.powercap.enabled` was true

## 1.0.0 (2026-06-24)

### Added

- Initial release of the OCUDU CU-CP (Control Plane) Helm chart, split from `ocudu-cu`
