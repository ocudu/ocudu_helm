# Changelog

## 3.6.0

### Changed
- **Default securityContext tightened to minimum-privilege shape.**
  - `capabilities.drop: [ALL]` + `capabilities.add: [SYS_NICE, IPC_LOCK]` (was 5 caps added, no drop).
  - `podSecurityContext` defaults to non-root: `runAsNonRoot: true`, `runAsUser: 1000`, `runAsGroup: 1000`, `fsGroup: 1000`.
  - `allowPrivilegeEscalation: true` (required for file caps to take effect on execve).
  - **Requires image with** `setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/gnb` and libraries findable via `ld.so.conf` (not only `LD_LIBRARY_PATH`).
  - **Requires node containerd with** `device_ownership_from_security_context = true`.
  - See [docs/security.md](docs/security.md) for the full prerequisite discussion.
- **values-o1.yaml**: mirrors the same securityContext + podSecurityContext defaults.

## 3.5.3 (2026-04-09)

### Changed
- Maintenance: bump version due to shared CI pipeline update in helm_utils.yml
- CI: `helm publish-dev` now requires `helm lint` and `helm version check` to pass before running

## 3.5.2 (2026-04-08)

### Changed
- Maintenance: fix issue in REUSE compliance headers.

## 3.5.1 (2026-04-08)

### Changed
- Maintenance: REUSE compliance headers and licensing metadata.

## 3.5.0 (2026-03-30)

### Changed
- Update default image to OCUDU 26.04
- Fix README license badge: AGPL-3.0 → BSD-3-Clause-Open-MPI

## 3.4.0 (2026-03-13)

### Added
- deployment: Add optional volume mount for Grafana for power measurement metrics via /sys/class/powercap

## 3.3.3 (2026-03-13)

### Fixed
- entrypoint: Replace MAC address lookup with sysfs/ip-link approach, avoiding the need for `CAP_SYSLOG`. Falls back to dmesg only as last resort.

## 3.3.2 (2026-03-13)

### Changed
- entrypoint: Fix issue with replacing lcores correctly, only replace second braketed section

## 3.3.1 (2026-03-06)

### Added
- Add `extraLabels` values to apply custom labels to the Deployment and Pod template

## 3.3.0 (2026-03-02)

### Changed
- License: Updated from MIT to BSD 3-Clause Open MPI variant

## 3.2.0 (2026-02-02)

### Added
- metricsService: Added custom NodePort configuration support
- N2/N3 Service: Added ClusterIP and NodePort support
- SR-IOV Resource Management: Removed automatic `vfCount` injection, just use resources

### Fixed
- O1 Integration: Fixed entrypoint script to properly handle O1-generated configurations
- LoadBalancer IP: Fixed deployment template using incorrect variable name `LoadBalancerIP` instead of `loadBalancerIP`

## 3.1.0 (2026-02-01)

### Fixed
- Fixed logging. Issue: Polluting the return value when captured with command substitution

## 3.0.0 (2026-01-29)

### BREAKING CHANGES
- **Chart Renamed**: `srsran-project` → `ocudu-gnb` (no backward compatibility)
- **License Changed**: AGPL-3.0 → MIT
- **Repository Moved**: GitHub → GitLab (https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Container Registry Changed**: DockerHub → GitLab Container Registry
  - New image: `registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-gnb`

### Rebranding
- All references updated from srsRAN to OCUDU throughout code and documentation
- Updated copyright headers to 2021-2026 Software Radio Systems Limited
- Updated all URLs to point to new GitLab organization
- Updated Chart.yaml metadata (name, description, home, sources, keywords)
- Updated all template helper names from `srsran-cudu.*` to `ocudu-gnb.*`
- Updated all documentation files with OCUDU branding

### Migration from srsRAN Chart
This is a clean break from the srsRAN chart. To migrate:
1. Uninstall existing srsRAN chart deployment
2. Update your values files to reference new image registry
3. Install OCUDU chart with new chart name: `ocudu-gnb`
4. Note: Chart name change means all resource names will be different

## 2.4.0 (Final srsRAN Release)

### Added
- Entrypoint script validates HAL `eal_args` present when SR-IOV devices detected

### Fixed
- LoadBalancer service now correctly respects `service.enabled: false` when determining `USE_EXT_CORE`
- Log file paths must exist when `persistence.enabled: false` (use `/tmp/` for ephemeral logs)

### Changed
- Remove hardcoded `fullnameOverride` and `nameOverride` to support multiple instances in same namespace
- Remove hardcoded ServiceAccount name to support multiple instances
- Resource names now use `<release-name>-ocudu-gnb` pattern for uniqueness
- Users can now deploy multiple gNB instances (e.g., gnb1, gnb2) in the same namespace without conflicts

### Migration Guide
- If you relied on hardcoded names (`srsran-project-cudu-chart`, `srsadmin-gnb`), you may need to:
  - Update RBAC references to use new ServiceAccount names
  - Update any external tools/scripts that reference the old resource names
  - Use `fullnameOverride` in your values if you need to maintain old names

## 2.3.1 (November 06, 2025)

### Changed
- Fixed issue with restart behaviour when O1 is enabled

## 2.3.0 (November 04, 2025)
### Added
- Expose a dedicated `*-o1` Service when the O1 bundle is enabled
- Package the CU/DU entrypoint helper in its own ConfigMap

### Changed
- Update the default CU/DU example config to comply with OCUDU 25.04
    - rotate log/pcap directories
    - derive HAL CPU sets from cgroup limits
    - map SR-IOV BDFs to cells before starting the gNB
- Update the O1 adapter arguments to comply with the new syntax

## 2.2.0 (September 18, 2025)
### Added
- Add service for Telegraf metrics collection
- Refactor configMap naming to support multiple instances deployment
### Changed
- Refactor entrypoint script to update HAL section
- Update entrypoint to return exit code of gNB process
- Update PID of the gNB process before calling kill
- Improve hostnetwork adaptation for gNB Pod
- Fix symlink creation and path handling in entrypoint
- Fix default value of PRESERVE_OLD_LOGS
- Create symlink to current log folder
- Save stdout in separate file

## 2.1.0 (April 16, 2025)
### Changed
- Forward SIGINT in the gNB entrypoint script to child processes.
- Forward SIGTERM in case the pod is killed externally.
- Preserve logs by creating a folder instead of appending a timestamp to old files.
- Fix several env‑var inclusion bugs in the Deployment template.
- Add functionality to avoid overwriting old logs on restart.
- Add a license header to the gNB entrypoint script.
- Provide an example `values.yaml` for LB + SR‑IOV plugin setups.
- Refactor and expand comments in `values.yaml`.
- Document needed `securityContext` when LB is enabled.
- Add a note about `hostNetwork` in LB‑enabled scenarios.
- Introduce an SR‑IOV-aware entrypoint script for gNB pods.
- Expose a LoadBalancer for N2, N3 and O1 interfaces.
- Fix indentation and formatting in `deployment.yaml`.
- Update and standardize the `README.md` for the chart.
- Switch the gNB command syntax to the new format.
- Retry gNB startup if it shuts down successfully.
- Fix the `postStart` hook for the O1 Adapter container.
- Add helpers to allow SHA‑256 digests as well as plain tags.
- Extend the example `o1_values.yaml` with a HAL section.
- Fix Netconf volume mounts in the StatefulSet.
- Correct paths for O1 config in the adapter.
- Correct the path of the `gnb.yaml` config template.
- Add an example `values-o1.yaml` for full O1 setup.

## 1.1.0 (November 04, 2024)
### Changed
- Update default chart config to match the 24.10 upstream release.
- Write the ConfigMap directly from `values.yaml` (no intermediate staging file).
- Append a suffix to all log and pcap filenames.
- Update the Docker image name in the Deployment.
- Fix issues in `configmap.yaml` and strip leftover comments.
- Allow toggling `hostNetwork` via `values.yaml`.
- Upgrade DPDK to 23.11
- Add initial version of RU Emulator
- Add option to store log files on node
- Fix DNS issues with dnsPolicy

## 1.0.0 (December 20, 2023)
### Added
- Deploys the OCUDU gNB with configurable parameters
- Moved config over to values.yaml
- Added autostart metrics

## 0.1.0 (September 29, 2023)
### Added
- Initial release of the srsRAN Project Helm chart
