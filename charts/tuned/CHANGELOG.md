# Changelog

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


## 0.5.1 (Unreleased)

### Changed
- Add complete Chart.yaml metadata (home, sources, keywords, icon)
- Add comprehensive .helmignore file
- Add Artifact Hub annotations
- Standardize README documentation structure
- Enhanced prerequisites section with clear requirements
- Added Overview section with capabilities
- Added Verifying Installation section
- Restructured Configuration with Key Parameters table
- Improved Common Configuration Examples section
- Added Architecture & Design section with accurate explanation of:
  - How the chart uses nsenter to execute commands in host namespace
  - Profile deployment process and host tuned daemon interaction
  - Checksum-based reboot mechanism and marker file system
  - Why privileged mode is required (hostPID, nsenter, host filesystem access)
- Enhanced Troubleshooting with host namespace commands
- Added Configuration Change Detection section explaining SHA256 checksum mechanism
- Added Support and License sections
- README now follows unified documentation standard

## 0.5.0 (Previous Release)

### Added
- Initial release of the tuned Helm chart
- Deploy tuned profiles via DaemonSet
- Support for custom tuned profiles
- System optimization for low-latency workloads
