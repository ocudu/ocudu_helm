# Changelog

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
