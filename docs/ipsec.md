# IPsec

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Each RAN chart can run a [strongSwan sidecar](../images/ipsec-sidecar/README.md) that
protects the interfaces between two pods you control, with IKEv2 and tunnel-mode ESP. It is
off by default and changes nothing until `ipsec.enabled` is set.

The model is one pod, one network namespace, one daemon, one IKE association per peer, and
one child association per protected interface. Because every pod has its own network
namespace, two RAN pods stay separate tunnel endpoints even when the scheduler puts them on
the same node.

Which interfaces a chart can protect depends on where the interface terminates. An
interface between two RAN pods is protectable only when both ends are pods running this
sidecar; an interface to the core (N2, N3) is protectable only when the core terminates
compatible IKEv2/IPsec. See
[What each chart protects](#what-each-chart-protects) for the per-chart list and the reason
behind it.

## Jump to

| If you want to… | Go to |
|---|---|
| see which interfaces your chart can protect | [What each chart protects](#what-each-chart-protects) |
| check the cluster, node and CNI prerequisites | [Requirements](#requirements) |
| learn how the protected addresses are laid out | [Addressing](#addressing) |
| find your chart's config key, sections and service keys | [Per-chart configuration](#per-chart-configuration) |
| set it up step by step (credentials, values, app config) | [Configuring it](#configuring-it) |
| copy a complete values block for your deployment | [Worked examples](#worked-examples) |
| &nbsp;&nbsp;• two gNBs over Xn | [gNB ↔ gNB (Xn)](#gnb--gnb-xn) |
| &nbsp;&nbsp;• two split CUs over Xn | [Xn between split CUs (Xn-C, Xn-U)](#xn-between-split-cus-xn-c-xn-u) |
| &nbsp;&nbsp;• a CU and a DU over F1 | [CU ↔ DU (F1)](#cu--du-f1) |
| &nbsp;&nbsp;• a split CU (CU-CP + CU-UP) and a DU | [CU-CP + CU-UP + DU (F1-C, F1-U, E1)](#cu-cp--cu-up--du-f1-c-f1-u-e1) |
| protect N2 or N3 to the core | [N2 and N3 to the core](#n2-and-n3-to-the-core) |
| issue certificates with cert-manager | [cert-manager](#cert-manager) |
| understand why `helm install` is refusing to render | [What the chart refuses to render](#what-the-chart-refuses-to-render) |
| know what is and is not protected | [Limits](#limits) |

## What it does

- Each protected interface gets its own XFRM interface inside the pod, with an address of
  its own, and the application binds to that address instead of the pod address.
- A single IKE association carries one child association per interface.
- The daemon runs as a sidecar that starts before the application and stops after it.
- With the default UDP encapsulation a NetworkPolicy allows the peer nothing but the
  tunnel, and the plaintext ports are not in the policy at all while IPsec is on. With
  `ipsec.encapsulation: native` the policy has to permit every protocol to the peer, which
  re-opens the plaintext ports to it — see [Encapsulation](#encapsulation).
- Before any tunnel interface exists the sidecar installs a route that refuses the whole
  protected range, so a protected address is never reachable by another path, not even for
  a moment.

The application container is not changed. It gains no capabilities and never sees the
private key.

## What each chart protects

An interface between two RAN pods can be carried in a tunnel only when the other end is a
pod running this same sidecar; an interface to the core can be carried only when the core
terminates compatible IKEv2/IPsec (see [N2 and N3 to the core](#n2-and-n3-to-the-core)).
That rules in the interfaces between RAN pods, rules the core interfaces in only behind
`protectN2` / `protectN3`, and rules out the ones that never reach the network stack.

| Chart | Protects | Optional, core-side | Never (and why) |
|-------|----------|---------------------|-----------------|
| `ocudu-gnb` | Xn-C, Xn-U | — | F1-C, F1-U, E1 are in-process connectors with no sockets; this chart defines no `protectN2` / `protectN3`, so it cannot carry N2 or N3 in a tunnel |
| `ocudu-cu` | F1-C, F1-U | N2 (`protectN2`), N3 (`protectN3`) | — |
| `ocudu-du` | F1-C, F1-U | — | fronthaul is a separate interface; a kernel-bypass datapath never reaches XFRM |
| `ocudu-cu-cp` | F1-C, E1 | N2 (`protectN2`) | — |
| `ocudu-cu-up` | F1-U, E1 | N3 (`protectN3`) | — |

**Xn** faces another gNB — a pod running this same sidecar — so it is the one O-RAN
interface that is always protectable where it exists. It is terminated by the full-node and
CU-side charts (`ocudu-gnb`, `ocudu-cu`, `ocudu-cu-cp` for Xn-C, `ocudu-cu-up` for Xn-U);
the DU has no Xn peer.

**N2 and N3** run to the core (AMF and UPF), which is not a pod this chart controls. They
are left in clear unless `ipsec.protectN2` / `ipsec.protectN3` is set and a core-side peer
terminates IKEv2. See [N2 and N3 to the core](#n2-and-n3-to-the-core).

Where an interface is in-process (the F1/E1 connectors inside a monolithic `ocudu-gnb`) or
runs over a kernel-bypass datapath, there is no packet in the kernel stack to intercept, so
there is nothing to encrypt.

## Requirements

**Kubernetes 1.29 or newer.** The sidecar is a sidecar init container, which is what makes
"IPsec is up before the application starts" an ordering guarantee rather than a race. The
chart refuses to render on anything older.

**The node.** The kernel has to provide XFRM, XFRM interfaces and ESP to an unprivileged
container holding `NET_ADMIN`. This is a property of the machine: no chart setting can
supply it, and the sidecar says so plainly if it is missing.

**Scheduling, where the node pins CPUs.** On a node whose kubelet runs the `static` CPU
manager policy, a container is given exclusive CPUs only while the whole pod is Guaranteed,
and that needs every container — the sidecar included — to have requests equal to its
limits. Give `ipsec.resources` matching requests and limits on such a node. Leave them
unequal and adding the sidecar drops the pod to Burstable, which takes the application
container's pinning with it.

> On the DPDK charts (`ocudu-gnb`, `ocudu-du`) this does not stay quiet for long: the
> entrypoint compares the CPU set the container was given against its CPU request and
> refuses to start rather than run DPDK on cores it was not promised.

**Pod networking.** `network.hostNetwork` has to be false. With host networking the pod
shares the node's network namespace, so it is not a separate endpoint and its traffic
cannot be told apart from the node's.

**The CNI.** It has to:

- carry UDP 4500, and UDP 500, pod to pod; when `ipsec.encapsulation: native` is used, also
  carry ESP (IP protocol 50) pod to pod — without it IKE may complete but no protected
  payload can cross;
- not translate addresses for pod-to-pod traffic inside the cluster address range, because
  address translation breaks the peer-address detection IKE does;
- enforce NetworkPolicy, which is the layer that stops the application addressing the peer
  directly and sending in clear;
- give the pod an MTU large enough for the tunnel. The sidecar derives the tunnel MTU from
  the pod interface at start — it does not assume a value — but an already small pod MTU
  leaves less room.

One CNI difference is worth knowing about in advance. The egress rule that allows name
lookups names the cluster DNS pods, which is the narrow answer and works where the service
address is translated before policy is applied. Where policy is applied to the service
address itself, that rule matches nothing, every name lookup fails, and the side that has
to resolve its peer never connects. Set `networkPolicy.egress.dnsTo: []` to allow port 53
to any destination instead: wider on destinations, still only port 53.

## Addressing

Each protected interface gets its own XFRM interface inside the pod, numbered from
`ipsec.protectedSupernet`. For a CU-CP + CU-UP + DU deployment the three pods line up like
this:

```
DU pod                      CU-CP pod                      CU-UP pod
  ipsec-f1c 100.64.10.2  <->  ipsec-f1c 100.64.10.1
                              ipsec-e1  100.64.20.1  <->  ipsec-e1  100.64.20.2
  ipsec-f1u 100.64.30.2  <------------------------------>  ipsec-f1u 100.64.30.1 (to DU)
        \                           |                            /
         eth0 <pod address>  ==ESP in UDP==>  eth0 <pod address>
```

The examples here follow one convention, a `/24` per interface inside
`ipsec.protectedSupernet` (default `100.64.0.0/16`):

| Interface | Subnet |
|---|---|
| F1-C | `100.64.10.0/24` |
| E1 | `100.64.20.0/24` |
| F1-U | `100.64.30.0/24` |
| Xn-C | `100.64.40.0/24` |
| Xn-U | `100.64.50.0/24` |
| N2 | `100.64.60.0/24` |
| N3 | `100.64.70.0/24` |

Nothing enforces it and the addresses are yours to choose, but keeping to it means two
charts configured separately do not land on the same one.

The inner addresses come from `ipsec.protectedSupernet` and are yours to choose. They exist
only inside the pods. The outer addresses are the pod addresses, which is why a peer is
named by a headless service: its record resolves straight to the pod address, and the name
is resolved again on every attempt, so a rescheduled peer is found at its new address. A
cluster IP service cannot carry this traffic — it forwards only the ports it declares and
it rewrites addresses.

`ifName` and `ifId` are derived from the connection name, so a connection is four keys:
the peer that carries it, the protocol, and the two protected addresses. Both can still be
set where a specific value is required. `ifId` is a local number — nothing about it is
negotiated or sent, so the two ends need not agree on it.

## Per-chart configuration

The concepts, requirements and steps below are the same for every chart. These are the
things that differ. Each worked example names its chart on the first line; use the row for
your chart when reading the steps.

| Chart | Application config key | Interface config sections | Service keys to disable |
|-------|------------------------|---------------------------|-------------------------|
| `ocudu-gnb` | `config.gnb-config.yml` | `cu_cp.xnap`, `cu_up.xnu` | none (F1/E1 are internal) |
| `ocudu-cu` | `config.cu-config.yml` | `cu_cp.f1ap`, `cu_up.f1u` (+ `cu_cp.amf`, `cu_up.ngu`) | `f1cService`, `f1uService` (+ `n2Service`, `n3Service`) |
| `ocudu-du` | `config.du-config.yml` | `f1ap`, `f1u` (flat; the DU schema is not nested) | `f1cService`, `f1uService` |
| `ocudu-cu-cp` | `config.cu-cp-config.yml` | `cu_cp.f1ap`, `cu_cp.e1ap` (+ `cu_cp.amf`) | `f1cService`, `e1Service` (+ `n2Service`) |
| `ocudu-cu-up` | `config.cu-up-config.yml` | `cu_up.f1u`, `cu_up.e1ap` (+ `cu_up.ngu`) | `f1uService`, `e1Service` (+ `n3Service`) |

The `amf`, `ngu`, `n2Service` and `n3Service` entries in parentheses apply only with
`ipsec.protectN2` / `ipsec.protectN3`; see [N2 and N3 to the core](#n2-and-n3-to-the-core).

The conditional `ipsec` keys that control the core-port checks exist only on the charts
that can carry the interface in question:

| Key | Present on | What it does |
|-----|-----------|--------------|
| `ipsec.allowF1uOnCorePort` | `ocudu-cu`, `ocudu-du`, `ocudu-cu-up` | override the F1-U-off-core-port check |
| `ipsec.allowXnuOnCorePort` | `ocudu-gnb`, `ocudu-cu`, `ocudu-cu-up` | override the Xn-U-off-core-port check |
| `ipsec.protectN2` | `ocudu-cu`, `ocudu-cu-cp` | carry N2 in a tunnel to the AMF |
| `ipsec.protectN3` | `ocudu-cu`, `ocudu-cu-up` | carry N3 in a tunnel to the UPF |

For the full list of `ipsec` keys and their defaults, see the `ipsec:` block in your
chart's `values.yaml`, for example
[`charts/ocudu-cu/values.yaml`](../charts/ocudu-cu/values.yaml).

## Configuring it

### 1. The credentials

Create a secret holding `tls.crt`, `tls.key` and `ca.crt`, and name it in
`ipsec.certSecret`. The two ends need certificates from the same certificate authority, and
each end's `localId` has to match a subject alternative name of its own certificate.

**Choose that authority carefully — it is doing more work than it looks.** A peer is
accepted on exactly two things: its certificate chains to the authority in `ca.crt`, and its
identity matches the `id` configured for that peer. A certificate's extended key usage is
not among the checks, so a certificate issued by that authority for the expected identity is
accepted whatever purpose it was issued for. Use an authority dedicated to these tunnels
rather than a general-purpose one that also serves other systems.

```bash
kubectl create secret generic <release>-ipsec \
  --from-file=tls.crt=this-pod.crt --from-file=tls.key=this-pod.key --from-file=ca.crt=ca.crt
```

Anything that produces those three files works. `ipsec.certManager` can issue them instead,
if cert-manager is installed — see [cert-manager](#cert-manager).

### 2. The values

Every peer this pod talks to is an entry under `ipsec.peers`, and every protected interface
is an entry under `ipsec.connections` naming the peer that carries it. A peer whose
`address` is set is one this pod dials; a peer without one is a peer this pod waits for.
Either side can be the one that starts.

With a single peer the `peer` key on a connection may be left out. It becomes required the
moment a second peer appears, because then which association carries an interface is a real
choice and guessing it wrong puts that interface on an association whose peer identity is
not the one that owns it.

See [Worked examples](#worked-examples) for a complete values block per deployment shape.

### 3. Point the application at the protected addresses

The chart does not rewrite the application config; it checks it. Every `local` address in
`ipsec.connections` has to appear in the interface config sections for your chart (see the
[Per-chart configuration](#per-chart-configuration) table), and those sections must not
bind a wildcard address. A wildcard leaves the application listening on the pod address as
well, which is the path the tunnel exists to close, so the chart refuses to render it. An
address written as a list item is read the same as one written beside its key.

The control-plane section names the peer's protected address (`f1ap.addrs` /
`xnap.gateways[].connections[].peer_addrs` — the same value as the connection's `remote`),
while the user-plane interface needs no peer address in the config: the tunnel endpoints are
signalled inside F1AP/XnAP, so binding the protected address is enough for the peer to learn
it. On the listening side of E1 (`cu_cp.e1ap.bind_addrs`) the section is a single flat bind
address; on the dialling side (`cu_up.e1ap.gateways[]`) it is a list, and only the addresses
inside a gateway entry are checked.

**The user-plane interface must not use the core's GTP-U port.** The policy has to let the
application reach the core on UDP 2152, and a NetworkPolicy rule names a port and an address
range, never a peer. The peer's pod address is inside that range, so while F1-U (or Xn-U)
uses 2152 that one rule also permits plaintext straight to the peer, around the tunnel. The
core's port is fixed; the RAN interface's is not, so it moves. Set the same port on both
ends:

```yaml
# chart: ocudu-cu
config:
  cu-config.yml: |-
    cu_up:
      f1u:
        bind_port: 2151
        peer_port: 2151
```

The chart refuses to render otherwise. Set `ipsec.allowF1uOnCorePort: true` (or
`ipsec.allowXnuOnCorePort: true` for Xn-U) only if there is no core to reach. With
`ipsec.protectN3` the policy opens no plaintext port to the core, so there is nothing to
share and the check does not apply.

### Narrowing a tunnel to one protocol

`connections.<name>.protocol` is optional. Set it — `sctp` for F1-C, E1 and Xn-C, `udp`
for F1-U and Xn-U — and the child's traffic selectors carry that protocol, so only it enters
the tunnel. Anything else between the two protected addresses then matches no policy: it
routes to the tunnel interface, finds no transform and is dropped, exactly as it would if
the tunnel were down.

Both ends write the same value. It is not narrowed by port as well, because the side that
dials an SCTP interface binds an ephemeral source port, so a port selector would have to
differ per side — an easy way to end up with one direction protected and the other not.

Leaving it out admits any protocol between the two addresses, which also admits ICMP and
so path-MTU discovery. On a UDP interface behind a smaller path MTU that may matter.

### Holding the application until the sidecar is set up

`ipsec.startupProbe` is on by default. The sidecar is a sidecar init container, so the
application does not start until this passes — which is what stops the application racing a
daemon that is still loading its configuration.

It checks that the daemon answers, that every protected interface appears in what the daemon
loaded, and that every tunnel interface exists carrying its address. It deliberately does
**not** check that a tunnel is up. A side that waits to be dialled has neither an association
nor a policy until its peer connects, and a failing startup probe restarts the container — so
a stricter check here would turn a slow peer into a crash loop. `ipsec.readinessProbe`
answers the "is a tunnel up" question, and is off by default for the same reason.

The check that matters most is the second one: a value the daemon rejects takes its whole
connection with it, so a single bad proposal can leave the daemon running with nothing
loaded at all.

### Replay protection, and how fast a dead peer is noticed

`ipsec.ike.replayWindow` sets how far out of order a packet may arrive and still be
accepted, in packets. It defaults to 32, which is the widest the kernel manages without
extended sequence numbers and is what the daemon would have used anyway — set explicitly so
the width is a number chosen here rather than one inherited.

It applies to the whole daemon, not to one interface: a replay window written into a child
section is accepted by the parser and then has **no effect at all**, which is why the chart
refuses a per-connection `replayWindow` rather than rendering something that does nothing.

**A window wider than 32 needs `esn` in `espProposal`.** Without it the kernel cannot hold a
bitmap that size and falls back to a window of **1** — narrower than if nobody had asked.
Nothing reports this, so the chart refuses the combination at render time:

```yaml
# chart: ocudu-cu
ipsec:
  ike:
    replayWindow: 1024
    espProposal: aes256gcm16-ecp256-esn
```

**A width of 0 switches replay protection off**, and that is refused too.

`ipsec.ike.retransmitTimeout` and `retransmitTries` decide how quickly a peer that has
stopped answering is given up on. This pair, not `dpdDelay`, is what governs it: the
daemon's defaults retry for about 165 seconds, and for all of that time this side keeps
encrypting into an association the peer no longer has. The defaults here are 2 seconds and
3 tries.

Both reach the daemon through a small configuration file the chart mounts beside the
image's own. Every setting in it is written twice, under `charon` and under
`charon-systemd`, because the daemon reads only the second and silently ignores a setting
written only under the first.

The remaining IKE knobs (`proposal`, `espProposal`, `dpdDelay`, `dpdTimeout`, `rekeyTime`)
are documented with their defaults in the `ipsec.ike` block of your chart's `values.yaml`.

`ipsec.logLevel` raises daemon verbosity when a negotiation will not complete: 0 silent,
1 negotiation, 2 more detail, 4 very verbose. 4 is not for a running deployment.

### Dropping a capability

`ipsec.ikeOnNatTPortOnly` carries IKE on UDP 4500 only. Nothing then binds a privileged
port, so the sidecar runs without `NET_BIND_SERVICE` and the policy opens one port instead
of two. **Both ends have to set it**: a peer still listening on 500 is never reached.

```yaml
# chart: ocudu-cu
ipsec:
  ikeOnNatTPortOnly: true
```

### Readiness

`ipsec.readinessProbe.enabled` reports the sidecar ready when the IKE association is up and
every protected interface has either a child association or the policy that stands in for
one until traffic arrives.

Turn it on for the side that starts the connection. The side that waits has neither until
its peer connects, so a probe there holds the pod unready for something that cannot have
happened yet. Traffic is protected either way — the probe reports, it does not enforce.

### Encapsulation

`ipsec.encapsulation` is `udp` by default: ESP inside UDP port 4500. That is portable, and
it is the only mode in which the NetworkPolicy can be exact. A policy can name only TCP,
UDP and SCTP, so with `native` — ESP as IP protocol 50 — the rule has to permit every
protocol to the peer, which re-opens the plaintext ports to the very peer the tunnel
protects. `native` saves 8 bytes per packet and costs that.

## Worked examples

Each block is one chart's values. Mirror it on the peer with `local` and `remote` swapped,
and set `peers.<name>.address` on exactly one side — that side dials, the other waits.

### gNB ↔ gNB (Xn)

Xn is the one O-RAN interface where both ends are pods you control, so it is protected
exactly as F1 and E1 are — pod to pod, no gateway in between.

**This example assumes a monolithic gNB on both ends**, so Xn-C and Xn-U both terminate on
the one peer pod: a single peer, a single address and a single IKE association carrying both
child connections. If either gNB is split (CU-CP + CU-UP + DU), Xn-C terminates on the
peer's CU-CP pod and Xn-U on its CU-UP pod — two pods, two headless-service addresses and
two peer identities — so the single-peer block below does not apply. See
[Xn between split CUs](#xn-between-split-cus-xn-c-xn-u) for that shape.

**Xn is symmetric and IKE is not, so pick a side and make both layers agree.** The side
carrying `peers.<name>.address` is the side that dials, so it is also the side that lists
the peer under `cu_cp.xnap.gateways[].connections[]`. The waiting side leaves both out and
sets `cu_cp.xnap.no_connection_init: true`, so neither layer opens the connection from that
end. Leave `ipsec.readinessProbe` off on the waiting side — it has no association until it
is dialled.

```yaml
# chart: ocudu-gnb
# gNB A — the side that starts
networkPolicy:
  enabled: true
  ingress:
    xn:
      enabled: true
  egress:
    xn:
      enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-gnb-ipsec
  localId: gnb-a.example.com
  peers:
    xn:
      id: gnb-b.example.com
      # The peer's headless service, which resolves straight to its pod address.
      address: ocudu-gnb-b-ipsec
  connections:
    xnc:
      peer: xn
      protocol: sctp
      local: 100.64.40.1
      remote: 100.64.40.2
    xnu:
      peer: xn
      protocol: udp
      local: 100.64.50.1
      remote: 100.64.50.2

config:
  gnb-config.yml: |-
    cu_cp:
      xnap:
        gateways:
          - bind_addrs:
              - 100.64.40.1
            connections:
              - peer_addrs:
                  - 100.64.40.2
    cu_up:
      xnu:
        bind_port: 2153
        peer_port: 2153
        socket:
          - bind_addr: 100.64.50.1
```

gNB B is the mirror image: `peers.xn.address` left empty, `local` and `remote` the other
way round, an empty `xnap.gateways[].connections` list, and
`cu_cp.xnap.no_connection_init: true` beside it.

Let the peer through the policy with `networkPolicy.ingress.xn` and
`networkPolicy.egress.xn`. Both are off by default, because a rule for a peer that does not
exist opens a port for nothing. With IPsec on they open the tunnel and nothing else.

The same Xn block applies to the CU-side charts that terminate Xn — `ocudu-cu` and
`ocudu-cu-cp` for Xn-C, `ocudu-cu-up` for Xn-U — with the config written under that chart's
config key. A CU-CP carries Xn-C only; a CU-UP carries Xn-U only.

### Xn between split CUs (Xn-C, Xn-U)

When the two gNBs either side of Xn are themselves split (CU-CP + CU-UP + DU), Xn is not one
tunnel between two pods but two tunnels between four: **Xn-C runs CU-CP ↔ CU-CP** (XnAP over
SCTP) and **Xn-U runs CU-UP ↔ CU-UP** (GTP-U over UDP). The DUs have no Xn peer. Each tunnel
is an independent IKE association between the two pods that terminate that interface, with
its own peer identity — there is no association that spans both halves of a gNB.

This is the gNB ↔ gNB block split across the two charts that own each interface. Pick a side
to start, as before: the side carrying `peers.<name>.address` dials and lists the peer in
its config; the waiting side leaves both out and sets `no_connection_init: true` on its
XnAP gateway. Below, gNB A starts both tunnels.

The CU-CPs carry Xn-C only:

```yaml
# chart: ocudu-cu-cp
# CU-CP A — the side that starts Xn-C
f1cService:
  enabled: false
e1Service:
  enabled: false

networkPolicy:
  enabled: true
  ingress:
    xn:
      enabled: true
  egress:
    xn:
      enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-cp-a-ipsec
  localId: cu-cp-a.example.com
  peers:
    xn:
      id: cu-cp-b.example.com
      # The peer CU-CP's headless service, which resolves straight to its pod address.
      address: ocudu-cu-cp-b-ipsec
  connections:
    xnc:
      peer: xn
      protocol: sctp
      local: 100.64.40.1
      remote: 100.64.40.2

config:
  cu-cp-config.yml: |-
    cu_cp:
      xnap:
        gateways:
          - bind_addrs:
              - 100.64.40.1
            connections:
              - peer_addrs:
                  - 100.64.40.2
```

CU-CP B is the mirror image: `peers.xn.address` left empty, `local` and `remote` swapped, an
empty `xnap.gateways[].connections` list, and `cu_cp.xnap.no_connection_init: true` beside
it. (A split-CU gNB also terminates F1-C and E1 on its CU-CP; add those peers and
connections as in [CU-CP + CU-UP + DU](#cu-cp--cu-up--du-f1-c-f1-u-e1). The Xn-C block above
is one more peer and one more connection on top of that.)

The CU-UPs carry Xn-U only:

```yaml
# chart: ocudu-cu-up
# CU-UP A — the side that starts Xn-U
f1uService:
  enabled: false
e1Service:
  enabled: false

networkPolicy:
  enabled: true
  ingress:
    xn:
      enabled: true
  egress:
    xn:
      enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-up-a-ipsec
  localId: cu-up-a.example.com
  peers:
    xn:
      id: cu-up-b.example.com
      # The peer CU-UP's headless service, which resolves straight to its pod address.
      address: ocudu-cu-up-b-ipsec
  connections:
    xnu:
      peer: xn
      protocol: udp
      local: 100.64.50.1
      remote: 100.64.50.2

config:
  cu-up-config.yml: |-
    cu_up:
      xnu:
        bind_port: 2153
        peer_port: 2153
        socket:
          - bind_addr: 100.64.50.1
```

CU-UP B is the mirror image, with `peers.xn.address` left empty and `local` and `remote`
swapped. As with the gNB example, keep Xn-U off the core's GTP-U port 2152 — the chart
refuses it otherwise — and set the same port on both ends; add the CU-UP's own F1-U and E1
peers as in [CU-CP + CU-UP + DU](#cu-cp--cu-up--du-f1-c-f1-u-e1).

Let each peer through the policy with `networkPolicy.ingress.xn` / `egress.xn`, both off by
default. On the CU-CP these open Xn-C (SCTP 38422) only; on the CU-UP they open Xn-U only.

### CU ↔ DU (F1)

The CU and the DU each run the sidecar and protect F1-C and F1-U. Either side may start;
below the DU starts, which suits it — it is the side that opens F1 anyway.

```yaml
# chart: ocudu-du
# DU — the side that starts
f1cService:
  enabled: false
f1uService:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-du-ipsec
  localId: du.example.com
  peers:
    cu:
      id: cu.example.com
      # The CU's headless service, which resolves straight to its pod address.
      address: <release>-ocudu-cu-ipsec
  connections:
    f1c:
      peer: cu
      protocol: sctp
      local: 100.64.10.2
      remote: 100.64.10.1
    f1u:
      peer: cu
      protocol: udp
      local: 100.64.30.2
      remote: 100.64.30.1

config:
  du-config.yml: |-
    f1ap:
      addrs: 100.64.10.1
      bind_addrs: 100.64.10.2
    f1u:
      socket:
        - bind_addr: 100.64.30.2
      bind_port: 2151
      peer_port: 2151
```

The CU is the mirror image, with `peers.cu.address` left empty and `local` and `remote` the
other way round. On the CU the config goes under `config.cu-config.yml` as
`cu_cp.f1ap.bind_addrs` and `cu_up.f1u`:

```yaml
# chart: ocudu-cu
# CU — the side that waits
f1cService:
  enabled: false
f1uService:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-ipsec
  localId: cu.example.com
  peers:
    du:
      id: du.example.com
  connections:
    f1c:
      peer: du
      protocol: sctp
      local: 100.64.10.1
      remote: 100.64.10.2
    f1u:
      peer: du
      protocol: udp
      local: 100.64.30.1
      remote: 100.64.30.2

config:
  cu-config.yml: |-
    cu_cp:
      f1ap:
        bind_addrs: 100.64.10.1
    cu_up:
      f1u:
        bind_port: 2151
        peer_port: 2151
        socket:
          - bind_addr: 100.64.30.1
```

### CU-CP + CU-UP + DU (F1-C, F1-U, E1)

Three pods, three protected interfaces: F1-C between DU and CU-CP, F1-U between DU and
CU-UP, E1 between CU-CP and CU-UP. Each pod has two peers and so two IKE associations, one
daemon. `connections.<name>.peer` names which association carries each interface, and that
is what decides which checked peer identity carries it.

The CU-CP waits for both peers (the DU opens F1-C, the CU-UP opens E1), so neither peer
needs an `address` here:

```yaml
# chart: ocudu-cu-cp
f1cService:
  enabled: false
e1Service:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-cp-ipsec
  localId: cu-cp.example.com
  peers:
    du:
      id: du.example.com
    cuup:
      id: cu-up.example.com
  connections:
    f1c:
      peer: du
      protocol: sctp
      local: 100.64.10.1
      remote: 100.64.10.2
    e1:
      peer: cuup
      protocol: sctp
      local: 100.64.20.1
      remote: 100.64.20.2

config:
  cu-cp-config.yml: |-
    cu_cp:
      e1ap:
        bind_addrs: 100.64.20.1
      f1ap:
        bind_addrs: 100.64.10.1
```

The CU-UP dials the CU-CP for E1 and waits for the DU on F1-U — the clearest example of a
pod doing both at once. A peer with an `address` is one it dials; a peer without one it
waits for:

```yaml
# chart: ocudu-cu-up
f1uService:
  enabled: false
e1Service:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-up-ipsec
  localId: cu-up.example.com
  peers:
    cucp:
      id: cu-cp.example.com
      # The CU-CP's headless service, which resolves straight to its pod address.
      address: <release>-ocudu-cu-cp-ipsec
    du:
      id: du.example.com
  connections:
    e1:
      peer: cucp
      protocol: sctp
      local: 100.64.20.2
      remote: 100.64.20.1
    f1u:
      peer: du
      protocol: udp
      local: 100.64.30.1
      remote: 100.64.30.2

config:
  cu-up-config.yml: |-
    cu_up:
      e1ap:
        gateways:
          - addrs: 100.64.20.1
            bind_addrs: 100.64.20.2
      f1u:
        bind_port: 2151
        peer_port: 2151
        socket:
          - bind_addr: 100.64.30.1
```

E1 is a list on the dialling side (`cu_up.e1ap.gateways`, one entry per gateway with its
own `addrs` and `bind_addrs`) and a single flat `cu_cp.e1ap.bind_addrs` on the listening
side. Only the addresses inside a gateway entry are checked against `ipsec.connections`.

The DU terminates both F1 interfaces, but on two different pods now, so unlike the
[CU ↔ DU](#cu--du-f1) example it needs **two** peers — the CU-CP for F1-C and the CU-UP for
F1-U — with each connection naming the peer that carries it. The DU dials both (it is the
side that opens F1), so each peer carries that pod's headless service name:

```yaml
# chart: ocudu-du
f1cService:
  enabled: false
f1uService:
  enabled: false

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-du-ipsec
  localId: du.example.com
  peers:
    cucp:
      id: cu-cp.example.com
      # The CU-CP's headless service, which resolves straight to its pod address.
      address: <release>-ocudu-cu-cp-ipsec
    cuup:
      id: cu-up.example.com
      # The CU-UP's headless service, which resolves straight to its pod address.
      address: <release>-ocudu-cu-up-ipsec
  connections:
    f1c:
      peer: cucp
      protocol: sctp
      local: 100.64.10.2
      remote: 100.64.10.1
    f1u:
      peer: cuup
      protocol: udp
      local: 100.64.30.2
      remote: 100.64.30.1

config:
  du-config.yml: |-
    f1ap:
      addrs: 100.64.10.1
      bind_addrs: 100.64.10.2
    f1u:
      socket:
        - bind_addr: 100.64.30.2
      bind_port: 2151
      peer_port: 2151
```

The DU dials both F1 interfaces, so `ipsec.readinessProbe` on it reports something that can
happen; turn it on there. The CU-CP waits for both its peers and the CU-UP waits for the DU
on F1-U, so each has an interface with neither an association nor a policy until its peer
dials in — leave the probe off on both, as in their blocks above.

## N2 and N3 to the core

N2 (to the AMF) and N3 (to the UPF) run to the core, which is not a pod this chart controls,
so they are left in clear unless `ipsec.protectN2` / `ipsec.protectN3` is set. With the
flag, the interface is carried in a tunnel like F1-C (N2) or F1-U (N3), to a core-side peer
that terminates IKEv2. The two flags are independent; set either or both where the chart
offers them (`protectN2`: `ocudu-cu`, `ocudu-cu-cp`; `protectN3`: `ocudu-cu`,
`ocudu-cu-up`). Each core-side peer is an association of its own.

### N2

This builds on the CU-CP from [CU-CP + CU-UP + DU](#cu-cp--cu-up--du-f1-c-f1-u-e1): it keeps
the F1-C and E1 connections and adds the AMF as a third peer with an N2 connection. The AMF
address and the `cu_cp.amf` bind addresses are the only new parts — everything else is the
F1-C/E1 setup unchanged.

```yaml
# chart: ocudu-cu-cp
f1cService:
  enabled: false
e1Service:
  enabled: false
n2Service:
  enabled: false   # refused while N2 is protected

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-cp-ipsec
  localId: cu-cp.example.com
  protectN2: true
  peers:
    du:
      id: du.example.com
    cuup:
      id: cu-up.example.com
    amf:
      id: amf.example.com
      # This pod opens N2, so it is the side that dials.
      address: <the AMF's IKE endpoint>
  connections:
    f1c:
      peer: du
      protocol: sctp
      local: 100.64.10.1
      remote: 100.64.10.2
    e1:
      peer: cuup
      protocol: sctp
      local: 100.64.20.1
      remote: 100.64.20.2
    n2:
      peer: amf
      protocol: sctp
      local: 100.64.60.1
      remote: 100.64.60.2

config:
  cu-cp-config.yml: |-
    cu_cp:
      e1ap:
        bind_addrs: 100.64.20.1
      f1ap:
        bind_addrs: 100.64.10.1
      amf:
        addrs: 100.64.60.2
        bind_addrs: 100.64.60.1
```

The `amf` and `extra_amfs` sections are then checked like the other protected sections: no
wildcard, no address outside `ipsec.connections`, and a `bind_addrs` in each entry. The
entrypoint stops binding N2 to the pod address, and the policy allows the core the tunnel
instead of plaintext SCTP 38412. Each extra AMF needs a connection of its own. (On
`ocudu-cu` the config key is `cu-config.yml`; the `cu_cp.amf` section is the same.)

### N3

This builds on the CU-UP from [CU-CP + CU-UP + DU](#cu-cp--cu-up--du-f1-c-f1-u-e1): it keeps
the E1 and F1-U connections and adds the UPF as a third peer with an N3 connection. The UPF
address and the `cu_up.ngu` bind address are the only new parts.

```yaml
# chart: ocudu-cu-up
f1uService:
  enabled: false
e1Service:
  enabled: false
n3Service:
  enabled: false   # refused while N3 is protected

networkPolicy:
  enabled: true

ipsec:
  enabled: true
  certSecret: ocudu-cu-up-ipsec
  localId: cu-up.example.com
  protectN3: true
  peers:
    cucp:
      id: cu-cp.example.com
      address: <release>-ocudu-cu-cp-ipsec
    du:
      id: du.example.com
    upf:
      id: upf.example.com
      # This pod sends the first uplink packet, so it is the side that dials.
      address: <the UPF's IKE endpoint>
  connections:
    e1:
      peer: cucp
      protocol: sctp
      local: 100.64.20.2
      remote: 100.64.20.1
    f1u:
      peer: du
      protocol: udp
      local: 100.64.30.1
      remote: 100.64.30.2
    n3:
      peer: upf
      protocol: udp
      local: 100.64.70.1
      remote: 100.64.70.2

config:
  cu-up-config.yml: |-
    cu_up:
      e1ap:
        gateways:
          - addrs: 100.64.20.1
            bind_addrs: 100.64.20.2
      f1u:
        bind_port: 2151
        peer_port: 2151
        socket:
          - bind_addr: 100.64.30.1
      ngu:
        socket:
          - bind_addr: 100.64.70.1
```

The `ngu` section is then checked like the other protected sections. The entrypoint stops
binding N3 to the pod address, and the policy allows the core the tunnel instead of
plaintext UDP 2152. `n3Service.advertisedAddress` is refused: the protected address is the
one advertised. (On `ocudu-cu` the config key is `cu-config.yml`; the `cu_up.ngu` section
is the same.)

**The uplink address comes from the core, not from this config.** The SMF sends the UPF's
N3 address in NGAP, so the chart cannot check it. The UPF has to advertise its protected
address (`remote` above). If the SMF hands out the UPF's regular N3 address instead, uplink
leaves outside the tunnel: with `udp` the policy drops it and uplink breaks without an
error, and with `native` it may go out in clear.

### The core side

The chart configures the RAN side only. The core side has to run its own IKEv2 endpoint,
reachable at `peers.<name>.address`, which:

- presents a certificate from the authority in `ca.crt` of `ipsec.certSecret`, with the
  identity in `peers.<name>.id`, and accepts `ipsec.localId` from this side;
- uses the proposals in `ipsec.ike.proposal` and `ipsec.ike.espProposal`, since this side
  offers exactly one of each;
- holds the `remote` address of the connection on the core host, binds its listener (N2) or
  GTP-U socket (N3) to it, and routes the `local` address back into the tunnel.

This side dials, so the core side only waits for it. With strongSwan on the core side, the
config mirrors the RAN side — `sctp` traffic selectors for N2, `udp` for N3:

```
# strongSwan on the core side (AMF shown; for N3/UPF use the n3 addresses and [udp])
connections {
  ran {
    version = 2
    proposals = aes256gcm16-prfsha384-ecp256
    local {
      auth = pubkey
      certs = amf.crt
      id = amf.example.com
    }
    remote {
      auth = pubkey
      id = cu-cp.example.com
    }
    children {
      n2 {
        local_ts = 100.64.60.2/32[sctp]
        remote_ts = 100.64.60.1/32[sctp]
        esp_proposals = aes256gcm16-ecp256
      }
    }
  }
}
```

## cert-manager

`ipsec.certManager.enabled` renders a `Certificate` that writes the secret named by
`ipsec.certSecret`. It requires the cert-manager custom resource definitions to be
installed, which is why it is off by default and why bringing your own secret stays the
supported path.

```yaml
# chart: ocudu-cu
ipsec:
  certManager:
    enabled: true
    issuerRef:
      name: ipsec-ca
      kind: ClusterIssuer
```

By default it asks for `localId` as a subject alternative name, which is right when that
identity is a name. Where it is not — a distinguished name, an email address — leave
`dnsNames` empty and put the matching field in `extraSpec`.

The sidecar watches the mounted secret and picks up a renewal on its own. When the contents
change it loads the new credentials, discarding what it held before, and closes the IKE
association so the next traffic authenticates with the new certificate. The pod is not
restarted. Expect it to take the time your cluster needs to update a mounted secret, plus
`ipsec.credentialReload.intervalSeconds`.

The child policies stay installed throughout, so protected traffic is encrypted or dropped
while the association is rebuilt, never sent in clear. Set
`ipsec.credentialReload.enabled: false` to turn the watch off.

## What the chart refuses to render

Each of these stops `helm install` with a message explaining why. None of them is a
warning, because a silent fall back to unprotected traffic is the one outcome this feature
exists to prevent. The **Applies to** column names the charts a row can fire on; rows with
no entry apply to every chart.

| Refused | Why | Applies to |
|---|---|---|
| `network.hostNetwork: true` | the pod is not a separate endpoint | all |
| `o1.enable_ocudu_o1: true` | in O1 mode the config is written at runtime, so it cannot be checked, and it can be changed again later | all |
| Kubernetes older than 1.29 | no sidecar init containers, so no ordering guarantee | all |
| `networkPolicy.enabled: false` | the application could still address the peer directly; override with `ipsec.allowWithoutNetworkPolicy` only where unprotected traffic is blocked some other way | all |
| an empty `ipsec.connections` | a sidecar protecting nothing | all |
| a duplicate or zero `ifId`, a duplicate or over-long `ifName` | two children sharing one tunnel, or no tunnel at all | all |
| a missing `certSecret`, `localId` or `peers.<name>.id` | without a peer identity any certificate the authority signed would be accepted, from anyone | all |
| an empty `ipsec.peers`, or a peer no connection names | the daemon would hold an association that protects nothing and report itself ready for it | all |
| a connection naming a peer that is not in `ipsec.peers`, or naming none while there is more than one | the interface would land on the wrong association, or on none | all |
| `connections.<name>.protocol` set to anything but `sctp`, `udp` or `tcp` | a selector naming a protocol the kernel does not match leaves the interface with no policy at all | all |
| `ipsec.ike.replayWindow` set to 0 | replay protection would be off, so a captured packet could be replayed and accepted | all |
| any `connections.<name>.replayWindow`, at any value | the replay window is a daemon-wide setting; a per-connection one is accepted by the parser and has no effect, so it would look configured and do nothing. Set `ipsec.ike.replayWindow` instead | all |
| `ipsec.encapsulation` set to anything but `udp` or `native` | there is no third way to carry ESP, and a typo would otherwise pick the default silently | all |
| a protected address in the config that is not in `ipsec.connections`, or a wildcard bind | traffic that would never enter the tunnel. An address written as a list item is read the same as one written beside its key | all |
| `f1cService` / `f1uService` / `e1Service` enabled | it publishes an unprotected path on the pod address | the charts that have that service: `f1cService` (cu, du, cu-cp), `f1uService` (cu, du, cu-up), `e1Service` (cu-cp, cu-up) |
| `bind_interface` set to anything but `auto` in a protected section | the socket is pinned to that device, so its traffic leaves there instead of through the tunnel | the gateway-schema charts: cu, cu-cp, cu-up |
| F1-U on the core's GTP-U port, 2152, unless `ipsec.protectN3` | the policy rule that lets the core be reached also permits plaintext F1-U to the peer; override with `ipsec.allowF1uOnCorePort` | cu, du, cu-up |
| Xn-U on the core's GTP-U port, 2152, unless `ipsec.protectN3` | the same rule, for the other user-plane interface that shares that port; override with `ipsec.allowXnuOnCorePort` | gnb, cu, cu-up |
| `ipsec.protectN2` without `ipsec.enabled` | there is no tunnel to carry N2, so it would stay in clear | cu, cu-cp |
| `n2Service` enabled with `ipsec.protectN2` | it publishes an unprotected path to N2 on the pod address | cu, cu-cp |
| no `bind_addrs` in `cu_cp.amf`, or in an entry of `cu_cp.extra_amfs`, with `ipsec.protectN2` | the application would bind 127.0.0.1 and N2 to that AMF would never come up | cu, cu-cp |
| `ipsec.protectN3` without `ipsec.enabled` | there is no tunnel to carry N3, so it would stay in clear | cu, cu-up |
| `n3Service` enabled, or `n3Service.advertisedAddress` set, with `ipsec.protectN3` | the service publishes an unprotected path to N3 on the pod address, and the advertised address would be ignored | cu, cu-up |
| no `bind_addr` in `cu_up.ngu.socket[]` with `ipsec.protectN3` | the application would bind 127.0.0.1 and N3 would never come up | cu, cu-up |

## Restarts

Either pod can be restarted and the tunnel comes back on its own. The side that starts the
connection installs a policy rather than a connection, and negotiates when the first packet
that matches it appears, so the application's own retries drive the reconnection and the
peer name is resolved again on each attempt.

How long that takes depends on which side moved. When the side that starts the connection
is the one that restarted, recovery takes as long as the application takes to retry. When
it is the **peer** that moved, and an attempt to reach its old address is already in
flight, the name is not resolved again until that attempt gives up — so expect minutes
rather than seconds. It still recovers without help.

## What this is not

This targets the IPsec requirements for the interfaces each chart protects. It is not a
compliance statement, and it claims nothing about any CNI beyond the requirements listed
above.

## Limits

- **O1 and IPsec cannot be combined.** In O1 mode the config comes from the datastore at
  runtime, so the chart cannot check that the application binds to the protected addresses,
  and the O1 interface could move it off them afterwards.
- **Each chart protects only the interfaces listed in
  [What each chart protects](#what-each-chart-protects).** For `ocudu-gnb` that is Xn and
  nothing else — F1-C, F1-U and E1 are in-process connectors that never reach the network
  stack. For `ocudu-du` it is F1 and nothing else. The fronthaul is a separate interface
  with its own requirements, and a kernel-bypass datapath does not pass through XFRM at all.
- **N2 and N3 are protected only with `ipsec.protectN2` and `ipsec.protectN3`** (on the
  charts that offer them). Each needs a core-side peer that terminates IKEv2 with a
  certificate from the same authority. Without the flag, the policy keeps its plaintext port
  for that interface and the chart makes no claim about it. See
  [N2 and N3 to the core](#n2-and-n3-to-the-core).
- **The chart cannot check the uplink N3 address.** The SMF supplies it at runtime, in
  NGAP. If it is not the UPF's protected address, uplink leaves outside the tunnel. See
  [N3](#n3).
- **Only one UPF is supported.** Every UPF the SMF may pick would have to be a peer with
  its own connection, and the chart cannot see which UPFs the SMF knows about. Uplink to a
  UPF that is not a peer leaves outside the tunnel.
- **A kernel-bypass datapath is not protected.** Traffic that never reaches the kernel
  network stack never reaches XFRM either. This applies to a user-plane interface carried
  over a bypass datapath (F1-U, N3), not to the control-plane interfaces (F1-C, E1, N2).
