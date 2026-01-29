# Changelog

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
