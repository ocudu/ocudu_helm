# Changelog

## 1.1.1 (Unreleased)

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
- Initial version of the srsRAN RU Emulator Helm chart