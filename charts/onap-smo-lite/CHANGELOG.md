# Changelog

## 1.1.0 (2026-03-02)

### Changed
- License: Updated from MIT to BSD 3-Clause Open MPI variant

## 1.0.0 (2026-01-29)

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


## 0.3.1 (Unreleased)

### Added

- **BREAKING**: Added mandatory `global.clusterDomain` parameter for cluster DNS configuration
- Parameterized all service FQDNs to use `global.clusterDomain`
- Enhanced Prerequisites section with cluster domain detection guide

### Changed

- **BREAKING**: All hardcoded cluster domain references (`srsk8s.bcn`) now use `global.clusterDomain` parameter
- Enhanced README with clearer "Integration PoC - No Support" warning
- Reorganized documentation for easier deployment
- Added prerequisites and verification steps
- Simplified configuration table with focus on essential parameters
- Added basic troubleshooting section
- Added OCUDU integration guidance

### Fixed

- Service FQDNs are now dynamically constructed based on cluster domain
- Templates properly use `tpl` function to evaluate cluster domain in service URLs

### Documentation

- Added mandatory configuration section for `global.clusterDomain`
- Improved installation instructions with cluster domain examples
- Added service access information (NodePort details)
- Clarified this is provided as-is with no support

### Migration Notes

**Users upgrading from previous versions MUST set `global.clusterDomain`:**
```bash
# Before (hardcoded in values.yaml):
# Various service URLs contained: .svc.srsk8s.bcn

# After (0.3.1+):
helm install/upgrade ... --set global.clusterDomain="cluster.local"
```

## 0.3.0 (Unreleased)

### Added

- Optional Kafka UI deployment and service for inspecting topics inside the SMO stack.

## 0.2.0 (Unreleased)

### Added

- Kafka broker, Zookeeper, and VES collector deployments mirroring the docker-compose stack.
- Configurable JAAS credentials and VES collector configuration via Helm values.

## 1.0.0 (October 29, 2025)

### Added

- Initial release of the ONAP ORAN-SC SMO Helm chart.
