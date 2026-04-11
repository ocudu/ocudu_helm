# Changelog

## 1.0.1 (2026-04-11)

### Added
- Add automatic hugepages volume and mount handling when `resources.requests` or `resources.limits` define `hugepages-1Gi` or `hugepages-2Mi`
- Update the DU entrypoint to rewrite `hal.eal_args` CPU masks from the container cgroup CPU set when a `hal` section is present

## 1.0.0 (2026-04-09)

### Added
- Initial version of the OCUDU DU Helm chart
