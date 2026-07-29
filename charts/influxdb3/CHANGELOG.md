# Changelog

## 2.4.0 (2026-07-29)

### Added
- A post-install/post-upgrade hook that creates the configured `database` with
  `retentionPeriod`, since InfluxDB3 Core accepts a retention period only at
  database-creation time. The hook warns instead of failing when the database
  already exists, because retention cannot be changed afterwards.
- `auth.tokenKey` for the raw administrator token used by clients.

### Fixed
- TLS material is copied to an emptyDir at mode 0600 by an init container
  instead of being mounted group-readable. Mounted Secrets are root-owned, so
  the previous 0440 mount was unreadable to the image's unprivileged
  `influxdb3` user unless the platform injected a matching fsGroup, and the
  server failed to start with `tls config error: Permission denied`.

### Changed
- Dropped the invalid `--retention-period` server argument: `influxdb3 serve`
  has no retention flag in any 3.x Core release.

### Notes
- Preconfigured admin tokens require InfluxDB3 Core `3.10.3-core` or newer;
  `3.1.0-core` rejects `--admin-token-file`. The chart default image tag is
  unchanged, so set `image.tag` when enabling authentication.
- Every default in this chart is unchanged from 2.2.3. Authentication, TLS,
  PVC storage, retained claims, and retention are all opt-in.

## 2.3.0 (2026-07-28)

### Added
- Existing Secret support for preconfigured InfluxDB3 admin tokens.
- Existing TLS Secret support with a configurable minimum TLS version.
- TCP readiness and liveness probes that work with authenticated HTTPS.
- Configurable PVC annotations and explicit extra server arguments.

### Changed
- No defaults changed. Authentication, TLS, file-backed PVC storage, retained
  claims, and retention are opt-in: enable them with `auth.enabled` plus
  `auth.adminToken.existingSecret`, `tls.enabled` plus `tls.existingSecret`,
  `persistence.type: pvc`, `persistence.pvc.annotations`, and
  `database` plus `retentionPeriod`.

## 2.2.3 (2026-04-09)

### Changed
- Maintenance: bump version due to shared CI pipeline update in helm_utils.yml
- CI: `helm publish-dev` now requires `helm lint` and `helm version check` to pass before running

## 2.2.2 (2026-04-08)

### Changed
- Maintenance: fix issue in REUSE compliance headers.

## 2.2.1 (2026-04-08)

### Changed
- Maintenance: REUSE compliance headers and licensing metadata.

## 2.2.0 (2026-03-20)

### Added
- `service.nodePort`: optional fixed NodePort when `service.type: NodePort`, enabling external access for distributed deployments

## 2.1.0 (2026-03-02)

### Changed
- License: Updated from MIT to BSD 3-Clause Open MPI variant

## 2.0.0 (2026-01-29)

### BREAKING CHANGES
- **License Changed**: AGPL-3.0 → MIT
- **Repository Moved**: Updated home URL to GitLab (https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Container Registry Changed**: Updated to GitLab Container Registry

### Rebranding
- Updated copyright headers to 2021-2026 Software Radio Systems Limited
- Updated all URLs to point to new GitLab organization
- Updated Chart.yaml metadata (home, sources, keywords: srsran → ocudu)
- Updated documentation references from srsRAN to OCUDU

### Migration
- Update your values files to reference new image registry
- No functional changes to the chart


## 1.1.0 (TBD)

### Added

- PVC support with `persistence.type` selector (pvc or hostPath)
- PVC templates for data and plugins volumes with configurable StorageClass
- Retention policy configuration examples in values.yaml
- Authentication configuration guidance for production use
- Storage abstraction pattern matching srsran-project

### Changed

- Enhanced README with concise storage, authentication, and retention documentation
- Reorganized persistence configuration in values.yaml
- Updated deployment.yaml to support both PVC and hostPath storage modes
- Improved values.yaml documentation with production warnings

### Fixed

- hostPath volume configuration now uses configurable pathType

## 1.0.0 (September 18, 2025)

### Added

- Initial release of the influxdb3 Helm chart.
