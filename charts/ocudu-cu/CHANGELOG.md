# Changelog

## 1.3.0 (2026-06-29)

### Added

- O1/NETCONF support gated on `o1.enable_ocudu_o1`: adds `ocudu-o1-adapter` and `netconf-server` sidecars, a NETCONF service (`service-o1.yaml`, NodePort/LoadBalancer with optional TLS on 6513), the `o1Config` ConfigMap, an O1-mode liveness probe, and the `o1.*` configuration values
- entrypoint.sh: wait for the O1-generated config before launching `ocu` (`ENABLE_OCUDU_O1`/`CONFIG_CREATE_TIMEOUT`)
- `values-o1.yaml`: example values preset with O1 enabled
- deployment.yaml: `PERFMON` capability on the CU container for powercap RAPL energy reads (`metricsService.powercap.enabled`)

### Changed

- values.yaml: default image repository changed from `ocudu_nightly_avx512` to `images/cu`
- deployment.yaml: set `dnsPolicy: ClusterFirstWithHostNet` on the pod spec

## 1.2.1 (2026-06-02)

### Added

- `emptyDir` volume mounted at `persistence.mountPath` when `persistence.enabled=false` — ensures log directory is always writable without requiring a hostPath or PVC

### Changed

- deployment.yaml: switch container command to `tini --` as PID 1 for zombie reaping and signal forwarding (fixes CNTi `specialized_init_system` and `zombie_handled` tests)
- values.yaml: document that `image.tag` must be quoted in values files to avoid YAML float parsing

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
