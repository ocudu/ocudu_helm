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
helm install linuxptp-ocudu oci://registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/linuxptp --version 2.4.0 \
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
kubectl get pods -l app.kubernetes.io/name=linuxptp

# View PTP logs
kubectl logs -l app.kubernetes.io/name=linuxptp -c linuxptp-chart-ptp4l

# Check synchronization (look for "rms" values in nanoseconds)
kubectl logs -l app.kubernetes.io/name=linuxptp -c linuxptp-chart-ptp4l | grep rms
```

Successful synchronization shows low RMS values:
```
ptp4l[123.456]: rms 25 max 45 freq +1234 +/- 12 delay 150 +/- 10
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
| `image.tag` | string | `"v4.4_2.2.0"` | Image tag (default: chart appVersion) |
| `nodeSelector` | object | `{}` | **RECOMMENDED**: Target nodes with PTP-capable NICs |
| `tolerations` | list | See values.yaml | Tolerations for scheduling (allows master nodes) |
| `resources` | object | `{}` | CPU/memory limits and requests |
| `config.dataset_comparison` | string | `"G.8275.x"` | PTP profile (G.8275.x for telecom) |
| `config.domainNumber` | string | `"24"` | PTP domain number (0-255) |
| `config.serverOnly` | string | `"0"` | 0=slave mode, 1=master mode |
| `config.ts2phc.enabled` | bool | `false` | Enable GNSS synchronization via ts2phc |
| `ptp4l.authentication.enabled` | bool | `false` | Enable LinuxPTP Authentication TLV configuration |
| `ptp4l.authentication.existingSecret` | string | `""` | Existing Secret containing the LinuxPTP SA file |
| `ptp4l.grandmasterAllowList.enabled` | bool | `false` | Enable source-MAC allow-listing for L2 PTP packets |
| `ptp4l.grandmasterAllowList.allowedSourceMacs` | list | `[]` | Legitimate GM source MAC addresses |
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

### With GM Source MAC Allow-Listing
```yaml
ptp4l:
  grandmasterAllowList:
    enabled: true
    allowedSourceMacs:
      - "00:11:22:33:44:55"
```

GM allow-listing drops L2 PTP packets from unknown source MAC addresses before
`ptp4l` sees them. It is not cryptographic authentication and can be bypassed by
MAC spoofing.

**Which MAC to allow-list**: the filters match the source MAC of the frames
arriving on the interface. In topologies with boundary clocks (e.g. G.8275.1)
that is the MAC of the *nearest* PTP node, not the grandmaster's own MAC.
Capture the address actually seen on the wire before enabling:

```bash
tcpdump -i <interface> -c 3 -e ether proto 0x88f7
```

Allow-listing the wrong MAC drops *all* PTP traffic and the pod will fail its
startup probe.

**Limitations**:
- Requires `config.network_transport: L2` (enforced at render time); UDP
  transports are not matched by the filters.
- VLAN-tagged PTP frames are not matched either — the pass and drop rules
  only apply to untagged `0x88f7` traffic.

**Filter lifecycle**: the chart owns `tc` filter preferences 38000-38099 on
the interface's `clsact` ingress (do not place other filters in this range).
Filters are removed on graceful shutdown (SIGTERM) and re-applied
idempotently on container start. After a non-graceful termination
(SIGKILL/OOM/forced pod deletion) the filters — including the drop rule —
remain on the host interface. Remove them manually if no replacement pod
takes over:

```bash
for p in $(seq 38000 38099); do
  tc filter del dev <interface> ingress pref $p 2>/dev/null
done
```

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

## Troubleshooting

### Pod not starting
```bash
# Check events
kubectl describe pod -l app.kubernetes.io/name=linuxptp

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
kubectl logs <pod> -c linuxptp-chart-ptp4l | grep "selected best master"

# Common issues:
# - No PTP grandmaster on network
# - Wrong PTP domain number
# - Network filters blocking PTP multicast (01:1B:19:00:00:00 for the default E2E delay mechanism; 01:80:C2:00:00:0E only applies to P2P)
```

### Poor synchronization accuracy
```bash
# Check RMS values (should be <100ns for good sync)
kubectl logs <pod> -c linuxptp-chart-ptp4l | grep rms

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
