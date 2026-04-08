# Changelog

## 2.3.2 (2026-04-09)

### Added
- Add missing `templates/telegraf-deployments.yaml` to deploy one Telegraf pod per gNB entry in the `gnbs` list

## 2.3.1 (2026-04-08)

### Changed
- Maintenance: REUSE compliance headers and licensing metadata.
## 2.3.0 (2026-03-20)

### Added
- support for multiple gNBs via a `gnbs` list
- `gnbs` list: one Telegraf Deployment is created per entry, connecting to that gNB and tagging all metrics with `gnb_id` for per-gNB filtering in Grafana

## 2.2.0 (2026-03-20)

### Changed
- Replaced all remaining `srsran` references with `ocudu`: default database name, namespace in service DNS names, and WS_URL default
- Updated Telegraf config path from `/etc/srs/telegraf.conf` to `/etc/ocudu/telegraf.conf` to align with the Docker image build
- Updated `influxdb3` dependency to 2.2.0 (adds NodePort support)

### Migration
- If deploying in a non-default namespace, update `INFLUXDB3_EXTERNAL_URL`, `grafana.datasources.datasources.yaml.datasources[0].url`, and `telegraf.env.WS_URL` to match your namespace
- Default database name changed from `srsran` to `ocudu` — update any existing InfluxDB3 data or override `influxdb3.database.name` and `INFLUXDB3_BUCKET` in your values file

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

