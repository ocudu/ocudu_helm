# Changelog

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
