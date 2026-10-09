# linuxptp

![PoC/Demo](https://img.shields.io/badge/status-PoC%2FDemo-yellow)

A Helm chart for deploying LinuxPTP (PTP4l, PHC2SYS, TS2PHC) for precise time synchronization in Kubernetes

> **⚠️ PoC/Demo Chart - Not Production Ready**
>
> This chart is intended for **development, testing, and demonstration purposes only**.
> It has not been hardened or validated for production use.

## Overview

LinuxPTP provides IEEE 1588 Precision Time Protocol (PTP) implementation for sub-microsecond time synchronization, critical for 5G RAN and other time-sensitive applications.

**Components**:
- **ptp4l**: PTP daemon for clock synchronization (IEEE 1588-2019)
- **phc2sys**: Synchronizes system clock to PTP Hardware Clock (PHC)
- **ts2phc**: Synchronizes PHC to external time source (GPS/GNSS)

## Prerequisites

Before installing, ensure your environment meets these requirements:

1. **Hardware**: Network interfaces with hardware timestamping support (e.g., Intel E810, Mellanox ConnectX-5)
2. **Kernel**: Linux kernel with PTP support enabled
3. **Privileges**: Chart requires `hostNetwork: true` and `privileged: true` for PTP clock access
4. **Node Selection**: Use `nodeSelector` to target nodes with PTP-capable NICs

## Installing the Chart

**Basic installation** (single interface):
```bash
helm install linuxptp-ocudu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/linuxptp --version 2.5.0 \
  --set interfaceNameList="ens3f0np0"
```

**Local installation**:
```bash
cd charts/linuxptp
helm install linuxptp ./ \
  --set interfaceNameList="ens3f0np0" \
  --set nodeSelector."kubernetes\.io/hostname"=node1
```

**Multiple interfaces** (dual PTP paths):
```bash
helm install linuxptp ./ \
  --set interfaceNameList="ens3f0np0;ens3f1np1"
```

## Verifying Installation

Check PTP synchronization status:
```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=linuxptp-chart

# View PTP logs
kubectl logs -l app.kubernetes.io/name=linuxptp-chart -c linuxptp-ptp4l

# Check synchronization (look for "rms" values in nanoseconds)
kubectl logs -l app.kubernetes.io/name=linuxptp-chart -c linuxptp-ptp4l | grep rms
```

Successful synchronization shows low RMS values:
```
ptp4l[123.456]: rms 25 max 45 freq +1234 +/- 12 delay 150 +/- 10
```

The ptp4l container also logs port state, parent, grandmaster and timeout
events, and a status line every 60 seconds:
```
ptp4l monitor: status SLAVE offset -3.0 ns path delay 512.0 ns parent 001122.fffe.334455-1 grandmaster 001122.fffe.334466 class 6 announce timeouts 0 sync timeouts 0
```

## Uninstalling the Chart

```bash
helm uninstall linuxptp
```

The command removes all Kubernetes components associated with the chart.


## Configuration

### Key Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `interfaceNameList` | string | `"ens3f1np1"` | **REQUIRED**: Semicolon-separated list of PTP-capable network interfaces |
| `image.repository` | string | `"registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/linuxptp"` | Container image repository |
| `image.tag` | string | `"v4.4_2.3.0"` | Image tag (default: chart appVersion) |
| `nodeSelector` | object | `{}` | **RECOMMENDED**: Target nodes with PTP-capable NICs |
| `tolerations` | list | See values.yaml | Tolerations for scheduling (allows master nodes) |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `config.dataset_comparison` | string | `"G.8275.x"` | PTP profile (G.8275.x for telecom) |
| `config.domainNumber` | string | `"24"` | PTP domain number (0-255) |
| `config.serverOnly` | string | `"0"` | 0=slave mode, 1=master mode |
| `config.ts2phc.enabled` | bool | `false` | Enable GNSS synchronization via ts2phc |
| `ptp4l.authentication.enabled` | bool | `false` | Enable LinuxPTP Authentication TLV configuration |
| `ptp4l.authentication.existingSecret` | string | `""` | Existing Secret containing the LinuxPTP SA file |
| `ptp4l.offsetLimitNs` | int | `25` | Offset limit of the synchronization check |
| `ptp4l.meanPathDelayLimitNs` | int | `0` | Mean path delay limit of the synchronization check (0 = off) |
| `ntp.enabled` | bool | `false` | Sync to NTP before starting PTP |

### Complete Parameter List

For the full list of available parameters, see [`values.yaml`](values.yaml).

For PTP configuration details, refer to the [LinuxPTP Documentation](https://linuxptp.nwtime.org/documentation/default/).

## Common Configuration Examples

### Basic PTP Slave (Telecom Profile)
```yaml
interfaceNameList: "ens3f0np0"
nodeSelector:
  kubernetes.io/hostname: worker-node-1

config:
  dataset_comparison: "G.8275.x"
  domainNumber: "24"
  serverOnly: "0"  # Slave mode
```

### Dual-Interface Setup for LLS-C1
```yaml
interfaceNameList: "ens3f0np0;ens3f1np1"

resources:
  limits:
    cpu: 1
    memory: 500Mi
  requests:
    cpu: 500m
    memory: 256Mi

config:
  serverOnly: 1
  clientOnly: 0
```

### With GNSS Synchronization
```yaml
interfaceNameList: "ens3f0np0"

config:
  ts2phc:
    enabled: true
    ts2phc_nmea_serialport: /dev/gnss0
    ts2phc_extts_polarity: rising
```

### With Authentication TLV
```bash
kubectl create secret generic linuxptp-sa \
  --from-file=sa.cfg=/path/to/operator-provided-sa.cfg
```

```yaml
ptp4l:
  authentication:
    enabled: true
    existingSecret: linuxptp-sa
    secretKey: sa.cfg
    spp: 0
    activeKeyId: 1
```

The chart mounts an existing SA file and renders LinuxPTP Authentication TLV
settings. It does not create keys or configure the grandmaster. Configure
matching Authentication TLV settings on all participating PTP peers.

The SA file uses the LinuxPTP `sa_file` syntax (see `ptp4l(8)`):

```
[security_association]
spp 0
seqid_window 20
1 SHA256 HEX:<64-hex-char-key>
```

Key lines use the format `key_id key_type [key_len] key` with key types
`SHA256-128`, `SHA256`, `AES128` and `AES256`. Keys are parsed as raw ASCII
by default; use an `ASCII:` or `HEX:` prefix to be explicit.

If you override `ptp4l.authentication.saFile` or `mountPath`, note that they
are coupled: the Secret key is mounted at `<mountPath>/<basename of saFile>`,
so `saFile` must point to a path inside `mountPath`.

**Keys**: generate a 256-bit key with `openssl rand -hex 32` and share it with
the other PTP nodes out of band. Keep SA files out of version control.

ptp4l reads the SA file only at start. After changing the Secret, restart the
pods with `kubectl rollout restart daemonset/linuxptp-chart`. To rotate a key
without losing sync, add the new key under a new key ID on all nodes and
restart, then set `activeKeyId` to the new ID on all nodes, then remove the
old key.

### With VLAN-Tagged PTP

Create the VLAN subinterface on the host (for example `ens3f0np0.100`) and
use it in `interfaceNameList`. Check hardware timestamping on it with
`ethtool -T ens3f0np0.100`.

### Hardened Client Profile

`values-hardened.yaml` enables authentication and stricter client settings
(`clientOnly`, `clock_class_threshold 7`, `syncReceiptTimeout 3`, a bounded
`max_frequency`).
Pass it before your own values file, which sets the fields the profile leaves
empty:

```bash
helm install linuxptp ./ -f values-hardened.yaml -f my-values.yaml
```

```yaml
# my-values.yaml
interfaceNameList: "ens3f0np0"
ptp4l:
  # Above the path delay shown in the ptp4l status line
  meanPathDelayLimitNs: 1000
  authentication:
    existingSecret: linuxptp-sa
```

The profile only rejects PTP traffic. When the legitimate master is lost, the
pod becomes NotReady.

**Limitations**:
- Authentication requires the directly connected PTP node to support it.
  Without it, any PTP node on the network can become the master.
- No setting keeps the clock synchronized when the PTP path is cut.
- Authentication does not stop removal or delay of valid packets. Removal is
  detected by the receipt timeouts, added delay by `meanPathDelayLimitNs`.
- PTP packets are not filtered or rate limited on the host. Filter and police
  PTP on the switch port.
- `clock_class_threshold 7` also ignores a boundary clock in holdover.

## Architecture & Design

### Why hostNetwork and privileged are Required

**`hostNetwork: true`** is mandatory because:
- PTP messages use Layer 2 (Ethernet) multicast
- Hardware timestamping requires direct NIC access
- Cannot work through overlay networks (Calico, Flannel, etc.)

**`privileged: true`** is mandatory because:
- Direct access to `/dev/ptp*` devices (PTP Hardware Clocks)
- Network interface configuration (`SYS_NICE`, `NET_ADMIN` capabilities)
- System clock adjustments for phc2sys

### Deployment Model

- **DaemonSet**: Runs on every node (or selected nodes via nodeSelector)
- **One pod per node**: PTP synchronization is node-specific
- **Multiple containers**: ptp4l, phc2sys, and optionally ts2phc

### Probes and Detection

- **Liveness**: the process still responds (ptp4l answers management
  requests, phc2sys and ts2phc keep logging). A failure restarts the container.
- **Startup and readiness**: the clock is synchronized. For ptp4l: port in
  SLAVE state, offset within `ptp4l.offsetLimitNs` and, if set, mean path delay
  within `ptp4l.meanPathDelayLimitNs`. Loss of synchronization makes the pod
  NotReady without a restart. A node that never synchronizes restarts its
  containers when the startup probe gives up (5 minutes).
- A container exits when its PTP process stops.

Detection times with the default values:

| Event | Setting | Time |
|-------|---------|------|
| No Announce | `announceReceiptTimeout` × 2^`logAnnounceInterval` | 375-500 ms |
| No Sync | `syncReceiptTimeout` × 2^`logSyncInterval` | off (190 ms with the hardened profile) |
| Offset or path delay above the limit | `ptp4l.offsetLimitNs`, `ptp4l.meanPathDelayLimitNs` | next check (2 s) |
| Pod NotReady | readiness `failureThreshold` × `periodSeconds` | up to 15 s after the check fails |

## Troubleshooting

### Pod not starting
```bash
# Check events
kubectl describe pod -l app.kubernetes.io/name=linuxptp-chart

# Common issues:
# - Node doesn't have PTP-capable NIC
# - Interface name incorrect
# - Security context denied (privileged not allowed)
```

### No synchronization
```bash
# Check if hardware timestamping is working
kubectl exec -it <pod> -- ethtool -T <interface>

# Check PTP messages are being received
kubectl logs <pod> -c linuxptp-ptp4l | grep "selected best master"

# Common issues:
# - No PTP grandmaster on network
# - Wrong PTP domain number
# - Network filters blocking PTP multicast (01:1B:19:00:00:00 for the default E2E delay mechanism; 01:80:C2:00:00:0E only applies to P2P)
```

### Poor synchronization accuracy
```bash
# Check RMS values (should be <100ns for good sync)
kubectl logs <pod> -c linuxptp-ptp4l | grep rms

# Common causes:
# - Network congestion or jitter
# - NIC doesn't support hardware timestamping
# - CPU scheduling issues (set resource requests)
```

## Support

- **Documentation**: [LinuxPTP Official Docs](https://linuxptp.nwtime.org/)
- **PTP Standards**: IEEE 1588-2019, ITU-T G.8275.1/G.8275.2

## License

BSD 3-Clause Open MPI variant - See LICENSE file for details
