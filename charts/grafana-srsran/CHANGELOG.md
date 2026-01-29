# Changelog

## 1.3.1 (Unreleased)

### Changed
- Enhanced PoC/Demo warning with specific limitations (auth, TLS, credentials)
- Added production deployment recommendations
- **Documentation improvements**:
  - Added prerequisites section (dependency build instructions)
  - Added component versions table with pinned versions
  - Added configuration examples (credentials, metrics endpoint, storage, auth)
  - Added custom dashboards section
  - Added comprehensive troubleshooting guide
  - Added architecture diagram
  - Enhanced README with better structure
- Reorganized values.yaml with header documentation
  - Added PoC/Demo warning in file header
  - Documented dependency versions and sources
  - Clearer component descriptions

## 1.3.0 (2025-09-17)

### Changed
- Replace metrics server with Telegraf
- Migrate from InfluxDB 2 to InfluxDB 3
- Expose Grafana UI as NodePort service

## 1.2.0 (April 17, 2025)
### Changed
- Update InfluxDB image and tag in `values.yaml`.
- Fix the metrics-server image name in the dashboard sidecar.
- Add a `README.md` for chart usage and values reference.
- Remove unnecessary fields (e.g. old sample datasources) from `values.yaml`.
- Add Changelog for the chart.

## 0.1.0 (June 04, 2024)
### Added
- Initial version of the srsRAN Grafana Helm chart

