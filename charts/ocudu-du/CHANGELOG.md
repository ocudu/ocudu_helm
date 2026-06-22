# Changelog

## 1.3.0 (2026-06-22)

### Added

- O1/NETCONF support gated on `o1.enable_ocudu_o1`: adds `ocudu-o1-adapter` and `netconf-server` sidecar containers to the DU pod
- `service-o1.yaml`: NETCONF service (NodePort by default, optional LoadBalancer) exposing `o1.o1Port`, plus the optional TLS port 6513
- `o1Config` ConfigMap (`o1-config.xml` ManagedElement template) rendered to the netconf-server when O1 is enabled, selected in place of the main `config` ConfigMap
- O1-mode liveness probe via the adapter's `/config-healthy` HTTP endpoint on `o1.healthcheckPort`, plus a `postStart` hook that notifies the adapter (`/restarted`) once it is healthy
- `o1.netconfServer.tls.{enabled,certSecret,tlsNodePort}` for the NETCONF-over-TLS endpoint on port 6513
- `o1.*` values: `netconfServerAddr`, `o1Port`, `healthcheckPort`, `oamIpv4Address`, `log_level`, `ws.*`, `ves.*`, `o1Adapter.{image,resources,securityContext}`, `netconfServer.{image,service,resources,securityContext}`
- entrypoint.sh: `ENABLE_OCUDU_O1`/`CONFIG_CREATE_TIMEOUT` handling — wait for the O1-generated config before launching `odu`, and remove it between restart iterations
- `configmap.o1.nameOverride` value and `ocudu-du.o1ConfigmapName` template helper
- `values-o1.yaml`: example values preset with O1 enabled

### Changed

- values.yaml: default image repository changed from `ocudu_nightly_avx512` to `images/du-dpdk`
- deployment.yaml: set `dnsPolicy: ClusterFirstWithHostNet` on the pod spec

### Fixed

- entrypoint.sh: correct the SR-IOV `RESOURCE_EXTENDED` → env-var name conversion; the previous `tr` used mismatched sets and shifted the alphabet (`a`→`_`, `b`→`A`, …)

## 1.2.2 (2026-06-02)

### Changed

- Add `PERFMON` to default securityContext capabilities to allow exec of `odu` binary with file caps

## 1.2.1 (2026-06-02)

### Added

- `emptyDir` volume mounted at `persistence.mountPath` when `persistence.enabled=false` — ensures log directory is always writable without requiring a hostPath or PVC

### Changed

- values.yaml: document that `image.tag` must be quoted in values files to avoid YAML float parsing

## 1.2.0 (2026-06-01)

### Changed

- Rename default log/pcap paths from `/var/log/srs` to `/var/log/ocudu` in entrypoint.sh and values.yaml

## 1.1.0 (2026-06-01)

### Added

- SR-IOV device plugin resource allocation (`sriovConfig.enabled`, `sriovConfig.extendedResourceName`)
- `RESOURCE_EXTENDED` env var injected into container when SR-IOV is enabled
- CAP_PERFMON capability conditionally added when `metricsService.powercap.enabled=true`
- `POD_IP`, `HOSTNETWORK`, `OCUDU_LOG_DIR` env vars in deployment
- entrypoint.sh: SR-IOV DPDK support — BDF injection into `network_interface` and `du_mac_addr` discovery via sysfs/ip-link/dmesg
- entrypoint.sh: in-process restart loop with SIGTERM forwarding to odu
- entrypoint.sh: rendered config snapshot to `${OCUDU_LOG_DIR}/du-config-rendered.yml`
- NOTES.txt

### Changed

- Replace all SRS-specific references with OCUDU equivalents: `entrypoint-srsdu.sh` → `entrypoint-ocudu-du.sh`, `entrypoint-volume-srsdu` → `entrypoint-volume-ocudu-du`, `srs-logs` → `ocudu-logs`, `/var/log/srs` → `/var/log/ocudu`
- values.yaml: default config log/pcap paths updated from `/tmp` to `/var/log/srs`

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
