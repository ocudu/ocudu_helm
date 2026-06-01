# Changelog

## 1.1.0 (2026-06-01)

### Changed
- Replace all SRS-specific references with OCUDU equivalents: `entrypoint-srsdu.sh` → `entrypoint-ocudu-du.sh`, `entrypoint-volume-srsdu` → `entrypoint-volume-ocudu-du`, `srs-logs` → `ocudu-logs`, `/var/log/srs` → `/var/log/ocudu`

## 1.0.2 (2026-05-31)

### Changed

- entrypoint.sh: replace backgrounded `odu &` launch with `exec stdbuf -oL odu -c <cfg>` so odu becomes the container process directly, eliminating block-buffered stdout delay
- entrypoint.sh: remove manual `SIGTERM` handler and restart loop — tini and Kubernetes `restartPolicy` handle these respectively
- entrypoint.sh: replace `/tmp/du-config.yml` with `/var/log/srs/du-config.yml` as the working config copy path
- deployment.yaml: set `tty: true` and `stdin: true` on the container to force line-buffered stdout
- deployment.yaml: switch container command to `tini --` as PID 1 for zombie reaping and signal forwarding
- values.yaml: update default `persistence.mountPath` from `/tmp` to `/var/log/srs`

### Added

- Liveness and readiness probes (`pgrep odu`), gated on `livenessProbe.enabled` and `readinessProbe.enabled`

## 1.0.1 (2026-04-11)

### Added
- Add automatic hugepages volume and mount handling when `resources.requests` or `resources.limits` define `hugepages-1Gi` or `hugepages-2Mi`
- Update the DU entrypoint to rewrite `hal.eal_args` CPU masks from the container cgroup CPU set when a `hal` section is present

## 1.0.0 (2026-04-09)

### Added
- Initial version of the OCUDU DU Helm chart
