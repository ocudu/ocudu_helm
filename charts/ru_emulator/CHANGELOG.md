# Changelog

## 2.3.3 (2026-03-19)

### Added
- entrypoint: Add function to get assigned CPU cores from cgroup for deployments with SRIOV Device Plugin enabled

## 2.3.2 (2026-03-13)

### Fixed
- entrypoint: Replace MAC address lookup with sysfs/ip-link approach, avoiding the need for `CAP_SYSLOG`. Falls back to dmesg only as last resort.

## 2.3.1 (2026-03-06)

### Added
- Add `extraLabels` values to apply custom labels to the Deployment and Pod template

## 2.3.0 (2026-03-04)

### Added
- Add support for persistence of logs using PVCs with hostPath option
- Add filename parameter to config for log output file
- Add preserveOldLogs parameter to manage log file retention on hostPath mounts

## 2.2.0 (2026-03-03)

### Changed
- License: Updated from MIT to BSD 3-Clause Open MPI variant
- Fixed problem with deriving MAC address for ru_mac_addr field
- Update ConfigMap with new parameters (prach_format, vlan_tag, port IDs, etc.)
- Add `t2a_*` timing parameters to cell configuration rendering and defaults

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


## 1.2.0 (Unreleased)

### Added
- **SR-IOV Support Enhancement**: Full SR-IOV device plugin integration with automatic resource injection
- `sriovConfig.vfCount` parameter for requesting multiple SR-IOV VFs
- **Entrypoint Script**: Complete rewrite (216 lines) with structured logging and proper SR-IOV handling
- Automatic VF PCI address (BDF) detection and replacement in config
- Automatic MAC address extraction from dmesg and replacement in config
- Comprehensive SR-IOV mode documentation with production-ready examples
- Network modes comparison (hostNetwork vs SR-IOV) in Architecture section
- SR-IOV auto-detection workflow documentation

### Changed
- **Deployment Template**: Now uses entrypoint script for all deployments (hostNetwork and SR-IOV)
- **ConfigMap**: Includes entrypoint.sh with proper executable permissions
- Enhanced `sriovConfig` section in values.yaml with detailed comments and examples
- Updated deployment template with SR-IOV resource request logic (matching srsran-project implementation)
- Enhanced README with separate hostNetwork and SR-IOV configuration examples
- Updated Architecture & Design section with detailed network modes explanation
- Enhanced Prerequisites section documenting both deployment modes
- Updated Key Parameters table with SR-IOV configuration options
- Improved security context documentation for SR-IOV mode (reduced privileges)

### Fixed
- Entrypoint script now correctly handles YAML structure with separate line for list marker (`-`)
- Proper replacement of network_interface with BDF and du_mac_addr with MAC
- Structured logging with timestamps (INFO/WARN/ERROR/FATAL)
- Signal handling for graceful shutdown (SIGTERM/SIGINT)

### Notes
- **Untested End-to-End**: SR-IOV implementation verified up to config replacement (BDF and MAC correctly detected and replaced). Full functional testing requires a custom container image containing the `/usr/local/bin/ru_emulator` binary (not present in standard OCUDU images). The entrypoint script and SR-IOV resource allocation are confirmed working through live cluster testing.

## 1.1.1 (2026-01-29)

### Changed
- Standardize Chart.yaml metadata with complete fields
- Add comprehensive .helmignore file
- Clean up verbose Chart.yaml comments
- Standardize README documentation structure
- Enhanced prerequisites section with clear requirements
- Added Overview section with capabilities
- Added Verifying Installation section
- Restructured Configuration with Key Parameters table
- Added Common Configuration Examples section
- Added Architecture & Design section explaining hostNetwork and privileged requirements
- Enhanced Troubleshooting with detailed solutions
- Added Support and License sections
- README now follows unified documentation standard
- Document requirement for custom container image with ru_emulator binary

## 1.1.0 (April 16, 2025)
### Changed
- Forward SIGTERM in the entrypoint script so the emulator shuts down cleanly.
- Add support for the SR‑IOV Device Plugin.
- Remove stray comments from `values.yaml` for clarity.
- Add Changelog for the chart.

## 0.1.0 (June 09, 2024)
### Added
- Initial version of the OCUDU RU Emulator Helm chart
