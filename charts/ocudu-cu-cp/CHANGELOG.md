# Changelog

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
