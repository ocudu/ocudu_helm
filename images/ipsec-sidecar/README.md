# OCUDU IPsec Sidecar Image

## Description

A strongSwan image for protecting O-RAN interfaces with IKEv2 and tunnel-mode ESP. It runs
as a sidecar inside a workload's pod and encrypts traffic at the network-namespace level, so
one pod is one IPsec endpoint no matter which machine it lands on — including when both ends
of a tunnel are on the same machine.

One sidecar runs one IKE daemon and carries as many protected interfaces as the workload
needs. A second daemon in the same network namespace would compete with the first for the
same ports, policies, states and routes, so there is only ever one.

## What it does not do

- **It does not decide anything.** The connection configuration arrives as a complete,
  already-rendered `swanctl.conf` and is used exactly as given.
- **It does not generate or hold a key of its own.** Credentials arrive on a read-only
  mount.
- **It does not fall back to plaintext.** If anything it was told to do fails, it exits and
  says why. A protected address is never reachable by a path that does not encrypt, not even
  during startup.

## Stages

| Stage | Contents |
|---|---|
| `runtime` | the daemon, `swanctl`, `iproute2`, the scripts. This is what ships. |
| `poc` | `runtime` plus SCTP, `socat`, `tcpdump`, `ping` and `iperf3`, for validating a network |

The `poc` stage exists to prove a tunnel carries traffic. The tools that do that are the
same tools that read traffic off a wire, so they stay out of the stage that runs next to a
live private key. Nothing should reference `poc` by default.

## What the pod must provide

| Requirement | Why |
|---|---|
| `NET_ADMIN` | to create tunnel interfaces and install policies in its own namespace |
| `NET_BIND_SERVICE` | to bind UDP/500. Not needed if IKE runs on UDP/4500 only |
| a writable `/run` | the daemon's control socket lives there |
| a writable `/etc/swanctl` | credentials are remapped into the layout the daemon expects |
| the credentials mount | `ca.crt`, `tls.crt` and `tls.key` |
| the configuration mount | `swanctl.conf` and `links.conf` |

The two writable paths are what make `readOnlyRootFilesystem: true` reachable — mount an
`emptyDir` at each. `privileged` is not needed, and neither is `NET_RAW`.

The entrypoint should run as the container's main process so that the daemon exiting ends
the container. There is no internal restart loop: a container restart re-runs every check
from the top, whereas a loop would turn a repeated failure into a quiet one.

## Configuration

### `swanctl.conf`

Standard strongSwan connection configuration, mounted and used unchanged. Each child
section needs `if_id_in` and `if_id_out` matching the interface ids in `links.conf`, because
that is what ties a child association to the interface its traffic arrives on.

### `links.conf`

The part `swanctl.conf` cannot express: the tunnel interfaces themselves. Five whitespace
separated columns, `#` begins a comment.

```
# child  ifname      if_id       local             peer
f1c      ipsec-f1c   0x00000101  100.64.10.1/32    100.64.10.2/32
f1u      ipsec-f1u   0x00000102  100.64.30.1/32    100.64.30.2/32
```

| Column | Meaning |
|---|---|
| `child` | the child section name in `swanctl.conf`. Also the list the readiness probe checks |
| `ifname` | the tunnel interface to create. At most 15 characters |
| `if_id` | the interface id, decimal or `0x` hex. Purely local, never negotiated, never zero |
| `local` | the protected address this side owns, with prefix length |
| `peer` | the protected subnets reached through this interface. Comma separated for several |

The child name is the first column on purpose. The readiness probe needs to know what must
be up, and that has to come from configuration. Asking the daemon what it loaded and then
checking those are up is a check that cannot fail for the reason it exists: a configuration
that never loaded reports no children at all, and every one of them is fine.

### Environment

| Variable | Default | Meaning |
|---|---|---|
| `IPSEC_CONFIG_DIR` | `/etc/ipsec-config` | where the two configuration files are mounted |
| `IPSEC_CREDENTIALS_DIR` | `/credentials` | where `ca.crt`, `tls.crt`, `tls.key` are mounted |
| `IPSEC_PROTECTED_SUPERNET` | `100.64.0.0/16` | the range the backstop route covers |
| `IPSEC_UPLINK` | `eth0` | the interface the tunnel MTU is derived from |
| `IPSEC_ENCAP` | `yes` | whether ESP is carried inside UDP |
| `IPSEC_TUNNEL_MTU` | derived | overrides the derived value |

## The tunnel MTU is derived, not assumed

A fixed value is wrong on any overlay network. The entrypoint reads the pod's own uplink MTU
and subtracts the worst case for tunnel-mode ESP with AES-GCM: 57 bytes, and 8 more when the
ESP is carried inside UDP. On a 1420-byte pod MTU that gives 1355, not 1400.

## Readiness

`readiness-ipsec.sh` reports ready only when every child listed in `links.conf` has an
association the kernel has installed. It reports **not ready** when it cannot reach the
daemon, when `links.conf` is missing, and when `links.conf` lists nothing — none of those
mean the tunnel is up, they mean nothing was measured.

## What the network must support

The image encrypts inside the pod, so most of what it needs is from the kernel rather than
from the network. Verify these on a machine before deploying to it; a missing kernel feature
is a property of the machine that no configuration can fix.

- XFRM, XFRM interfaces and ESP, usable by an unprivileged container holding `NET_ADMIN`
- reverse-path filtering in the pod namespace permissive enough for tunnelled traffic

From the network itself:

- UDP/4500 and UDP/500 carried pod to pod (or IP protocol 50 if ESP is not encapsulated)
- no source address translation between pods inside the cluster
- a pod MTU large enough to leave a usable tunnel MTU after the overhead above

Encapsulating ESP in UDP costs about eight bytes per packet and is the portable choice. It
is also the only mode a Kubernetes NetworkPolicy can describe exactly, because a policy can
name UDP ports but cannot name IP protocol 50 at all — so a policy for unencapsulated ESP
has to permit every protocol to the peer, which reopens the plaintext path the tunnel exists
to close.

## Versions

The strongSwan version comes from the distribution archive, so the version in the image tag
is an assertion rather than a checkout. `check-runtime-support.sh` verifies it during the
build, which is what stops the tag becoming untrue the first time the archive moves.
