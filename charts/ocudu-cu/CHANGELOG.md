# Changelog

## 1.2.0 (2026-06-01)

### Changed

- Rename default log/pcap paths from `/var/log/srs` to `/var/log/ocudu` in entrypoint.sh and values.yaml

## 1.1.0 (2026-06-01)

### Added

- Non-root `podSecurityContext` (uid/gid 1000) and minimum-privilege `securityContext` (SYS_NICE, IPC_LOCK)
- `network.hostNetwork` toggle with conditional `dnsPolicy`
- tini as PID 1 for signal forwarding and zombie reaping
- Liveness and readiness probes (`pgrep ocu`)
- `POD_IP`, `HOSTNETWORK`, `OCUDU_LOG_DIR` env vars in deployment
- N2/N3 service (`service.yaml`) — SCTP:38412 and UDP:2152
- Metrics service (`service-metrics.yaml`) — TCP:8001
- Network policy (`networkpolicy.yaml`) — N2/N3 + F1-C/F1-U + monitoring
- entrypoint.sh: IP override injection (POD_IP into `cu_cp.amf.bind_addr` and `cu_up.ngu.socket[].bind_addr`; `ext_addr` when `USE_EXT_CORE=true`)
- entrypoint.sh: in-process restart loop with SIGTERM forwarding to ocu
- entrypoint.sh: rendered config snapshot to `${OCUDU_LOG_DIR}/cu-config-rendered.yml`
- NOTES.txt

### Changed

- Replace all SRS-specific references with OCUDU equivalents: `entrypoint-srscu.sh` → `entrypoint-ocudu-cu.sh`, `entrypoint-volume-srscu` → `entrypoint-volume-ocudu-cu`, `srs-logs` → `ocudu-logs`, `SRS_LOG_DIR` → `OCUDU_LOG_DIR`, `/var/log/srs` → `/var/log/ocudu`
- `persistence.mountPath` default from `/tmp` to `/var/log/srs`
- Default config log/pcap paths updated from `/tmp` to `/var/log/srs`

## 1.0.0 (2026-04-09)

### Added
- Initial version of the OCUDU CU Helm chart
