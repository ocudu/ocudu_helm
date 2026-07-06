# Changelog

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
