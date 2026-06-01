# Changelog

## 2.2.0 (2026-06-01)

### Changed
- Replace all SRS-specific references with OCUDU equivalents: `rt-tests-srs` → `rt-tests-ocudu`

## 2.1.3 (2026-04-09)

### Changed
- Maintenance: bump version due to shared CI pipeline update in helm_utils.yml
- CI: `helm publish-dev` now requires `helm lint` and `helm version check` to pass before running

## 2.1.2 (2026-04-08)

### Changed
- Maintenance: fix issue in REUSE compliance headers.

## 2.1.1 (2026-04-08)

### Changed
- Maintenance: REUSE compliance headers and licensing metadata.

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


## 1.0.1 (TBD)

### Changed

- Standardize README documentation structure
- Enhanced prerequisites section with clear requirements
- Added Overview section with tool descriptions
- Added Verifying Installation section
- Restructured Configuration with Key Parameters table
- Added Common Configuration Examples section
- Added Architecture & Design section explaining privileged mode requirement
- Enhanced Troubleshooting with detailed solutions
- Added Support and License sections
- README now follows unified documentation standard

## 1.0.0 (March 26, 2025)

### Added

- Initial release of the rt-tests Helm chart.
