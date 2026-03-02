# Changelog

## 2.1.0 (2026-03-02)

### Changed
- License: Updated from MIT to BSD 3-Clause Open MPI variant

## 2.0.0 (2026-01-29)

### BREAKING CHANGES
- **Chart Renamed**: `grafana-srsran` → `grafana-ocudu`
- **License Changed**: AGPL-3.0 → MIT
- **Repository Moved**: Updated home URL to GitLab (https://gitlab.com/ocudu/ocudu_elements/ocudu_helm)
- **Dependency Updated**: influxdb3 chart now references GitLab repository (version 2.0.0)

### Rebranding
- Updated copyright headers to 2021-2026 Software Radio Systems Limited
- Updated all URLs to point to new GitLab organization
- Updated Chart.yaml metadata (name, home, sources, keywords: srsran → ocudu)
- Updated documentation references from srsRAN to OCUDU
- Updated influxdb3 dependency repository URL

### Migration
- Uninstall existing grafana-srsran deployment
- Install new grafana-ocudu chart
- Update dependency: `helm dependency update`
- No functional changes to the monitoring stack

## 1.3.1 (Final Pre-Rebranding Release)

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
- Initial version of the OCUDU Grafana Helm chart

