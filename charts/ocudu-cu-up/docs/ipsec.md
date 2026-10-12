# IPsec for F1-U and E1

The CU-UP chart can run a strongSwan sidecar that protects the F1-U and E1
interfaces with IKEv2 and
tunnel-mode ESP. It is off by default and changes nothing until `ipsec.enabled` is set.

The model is one pod, one network namespace, one daemon, one IKE association per peer, and
one child association per protected interface.

Because every pod has its own network namespace, the CU-UP, the CU-CP and the DU
stay separate tunnel endpoints even when the scheduler puts them on one node.

## What it does

- Each protected interface gets its own XFRM interface inside the pod, with an address of
  its own, and the application binds to that address instead of the pod address.
- A single IKE association carries one child association per interface.
- The daemon runs as a sidecar that starts before the application and stops after it.
- A NetworkPolicy allows the peer nothing but the tunnel. The plaintext F1 ports are not
  in the policy at all while IPsec is on.
- Before any tunnel interface exists the sidecar installs a route that refuses the whole
  protected range, so a protected address is never reachable by another path, not even for
  a moment.

The application container is not changed. It gains no capabilities and never sees the
private key.

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

**Pod networking.** `network.hostNetwork` has to be false. With host networking the pod
shares the node's network namespace, so it is not a separate endpoint and its traffic
cannot be told apart from the node's.

**The CNI.** It has to:

- carry UDP 4500, and UDP 500, pod to pod;
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

```
CU-CP pod                     CU-UP pod                      DU pod
  ipsec-e1  100.64.20.1  <->  ipsec-e1  100.64.20.2
                              ipsec-f1u 100.64.30.1  <->  ipsec-f1u 100.64.30.2
        \                           |                            /
         eth0 <pod address>  ==ESP in UDP==>  eth0 <pod address>
```

Two peers, two IKE associations, one daemon. The CU-CP carries E1 and the DU carries F1-U;
each connection names its peer with `connections.<name>.peer`, and that is what decides
which association — and so which checked peer identity — carries it.

This pod also shows both directions at once: it dials the CU-CP for E1 and waits for the DU
on F1-U. A peer with an `address` starts the connection; a peer without one waits.

The examples here follow one convention, a `/24` per interface inside
`ipsec.protectedSupernet`:

| Interface | Subnet |
|---|---|
| F1-C | `100.64.10.0/24` |
| E1 | `100.64.20.0/24` |
| F1-U | `100.64.30.0/24` |
| Xn-C | `100.64.40.0/24` |
| Xn-U | `100.64.50.0/24` |

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
kubectl create secret generic ocudu-cu-up-ipsec \
  --from-file=tls.crt=cu.crt --from-file=tls.key=cu.key --from-file=ca.crt=ca.crt
```

Anything that produces those three files works. `ipsec.certManager` can issue them instead,
if cert-manager is installed — see below.

### 2. The values

Every peer this pod talks to is an entry under `ipsec.peers`, and every protected interface
is an entry under `ipsec.connections` naming the peer that carries it. A peer whose
`address` is set is one this pod dials; a peer without one is a peer this pod waits for.

The CU-UP does both, which makes it the clearest example of the two: it dials the CU-CP for
E1, and waits for the DU on F1-U.

```yaml
# CU-UP
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

The DU sets `peers.<name>.address` to this pod's headless service —
`<release>-ocudu-cu-up-ipsec` — with `local` and `remote` the other way round.

### 3. Point the application at the protected addresses

E1 is configured as a list here: `cu_up.e1ap.gateways` takes one entry per gateway, each
with its own `addrs` and `bind_addrs`. The CU-CP side is a single flat `cu_cp.e1ap.bind_addrs`
because it listens rather than dials. Only the addresses inside a gateway entry are checked
against `ipsec.connections`.

The chart does not rewrite the application config; it checks it. Every `local` address in
`ipsec.connections` has to appear in the `f1u` and `e1ap` sections of the config, and those
sections must not bind a wildcard address. A wildcard leaves the application listening on
the pod address as well, which is the path the tunnel exists to close, so the chart refuses
to render it.

Note that F1-U needs no peer address in the config: the tunnel endpoints are signalled
inside F1AP, so binding the protected address is enough for the peer to learn it.

**F1-U must not use the core's GTP-U port.** The policy has to let the application reach the
core on UDP 2152, and a NetworkPolicy rule names a port and an address range, never a peer.
The peer's pod address is inside that range, so while F1-U uses 2152 that one rule also
permits plaintext F1-U straight to the peer, around the tunnel. The core's port is fixed;
F1-U's is not, so F1-U moves. Set the same port on both ends:

```yaml
cu_up:
  f1u:
    bind_port: 2151
    peer_port: 2151
```

The chart refuses to render otherwise. Set `ipsec.allowF1uOnCorePort: true` if there is no
core to reach.

### Narrowing a tunnel to one protocol

`connections.<name>.protocol` is optional. Set it — `sctp` for F1-C and E1, `udp` for
F1-U — and the child's traffic selectors carry that protocol, so only it enters the
tunnel. Anything else between the two protected addresses then matches no policy: it
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

`ipsec.logLevel` raises daemon verbosity when a negotiation will not complete: 0 silent,
1 negotiation, 2 more detail, 4 very verbose. 4 is not for a running deployment.

## Xn

Xn is the one O-RAN interface where both ends are pods you control, so it is protected
exactly as F1 and E1 are — pod to pod, no gateway in between. The peer is another gNB
running this same sidecar, split or monolithic.

```yaml
ipsec:
  peers:
    xn:
      id: gnb-b.example.com
      # Set on one side only. That side dials; the other waits.
      address: ocudu-gnb-b-ipsec
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

**Xn-U has to move off UDP 2152.** That is the port the policy has to leave open for the
core, and a policy rule names a port and an address range, never a peer — so while Xn-U
shares it, the rule opened for the core also permits plaintext Xn-U straight to the peer's
pod address, around the tunnel. The core's port is fixed in the application and Xn-U's is
not, so Xn-U is what moves. Both ends have to agree on the number. The chart refuses to
render otherwise; `ipsec.allowXnuOnCorePort` overrides it only where there is no core.


**One side starts and the other waits, and both layers have to agree which.** Xn is
symmetric; IKE is not. The side carrying `peers.<name>.address` is the side that dials, so
it is also the side that should list the peer under `cu_cp.xnap.gateways[].connections[]`.
The waiting side leaves both out and sets `cu_cp.xnap.no_connection_init: true`, so neither
layer opens the connection from that end. A waiting side has no association until it is
dialled, so leave `ipsec.readinessProbe` off there.

Let the peer through the policy with `networkPolicy.ingress.xn` and
`networkPolicy.egress.xn`. Both are off by default, because a rule for a peer that does not
exist opens a port for nothing. With IPsec on they open the tunnel and nothing else.

## What the chart refuses to render

Each of these stops `helm install` with a message explaining why. None of them is a
warning, because a silent fall back to unprotected traffic is the one outcome this feature
exists to prevent.

| Refused | Why |
|---|---|
| `network.hostNetwork: true` | the pod is not a separate endpoint |
| `o1.enable_ocudu_o1: true` | in O1 mode the config is written at runtime, so it cannot be checked, and it can be changed again later |
| Kubernetes older than 1.29 | no sidecar init containers, so no ordering guarantee |
| `f1uService` or `e1Service` enabled | they publish an unprotected path on the pod address |
| `networkPolicy.enabled: false` | the application could still address the peer directly; override with `ipsec.allowWithoutNetworkPolicy` only where unprotected traffic is blocked some other way |
| an empty `ipsec.connections` | a sidecar protecting nothing |
| a duplicate or zero `ifId`, a duplicate or over-long `ifName` | two children sharing one tunnel, or no tunnel at all |
| a missing `certSecret`, `localId` or `peers.<name>.id` | without a peer identity any certificate the authority signed would be accepted, from anyone |
| an empty `ipsec.peers`, or a peer no connection names | the daemon would hold an association that protects nothing and report itself ready for it |
| a connection naming a peer that is not in `ipsec.peers`, or naming none while there is more than one | the interface would land on the wrong association, or on none |
| `connections.<name>.protocol` set to anything but `sctp`, `udp` or `tcp` | a selector naming a protocol the kernel does not match leaves the interface with no policy at all |
| `ipsec.ike.replayWindow` or a connection's `replayWindow` set to 0 | replay protection would be off, so a captured packet could be replayed and accepted |
| `ipsec.encapsulation` set to anything but `udp` or `native` | there is no third way to carry ESP, and a typo would otherwise pick the default silently |
| a protected address in the config that is not in `ipsec.connections`, or a wildcard bind | traffic that would never enter the tunnel. An address written as a list item is read the same as one written beside its key |
| F1-U on the core's GTP-U port, 2152 | the policy rule that lets the core be reached also permits plaintext F1-U to the peer; override with `ipsec.allowF1uOnCorePort` |
| Xn-U on the core's GTP-U port, 2152 | the same rule, for the other user-plane interface that shares that port; override with `ipsec.allowXnuOnCorePort` |

## Dropping a capability

`ipsec.ikeOnNatTPortOnly` carries IKE on UDP 4500 only. Nothing then binds a privileged
port, so the sidecar runs without `NET_BIND_SERVICE` and the policy opens one port instead
of two. **Both ends have to set it**: a peer still listening on 500 is never reached.

```yaml
ipsec:
  ikeOnNatTPortOnly: true
```

## Readiness

`ipsec.readinessProbe.enabled` reports the sidecar ready when the IKE association is up and
every protected interface has either a child association or the policy that stands in for
one until traffic arrives.

Turn it on for the side that starts the connection. The side that waits has neither until
its peer connects, so a probe there holds the pod unready for something that cannot have
happened yet. Traffic is protected either way — the probe reports, it does not enforce.

## Encapsulation

`ipsec.encapsulation` is `udp` by default: ESP inside UDP port 4500. That is portable, and
it is the only mode in which the NetworkPolicy can be exact. A policy can name only TCP,
UDP and SCTP, so with `native` — ESP as IP protocol 50 — the rule has to permit every
protocol to the peer, which re-opens the plaintext F1 ports to the very peer the tunnel
protects. `native` saves 8 bytes per packet and costs that.

## cert-manager

`ipsec.certManager.enabled` renders a `Certificate` that writes the secret named by
`ipsec.certSecret`. It requires the cert-manager custom resource definitions to be
installed, which is why it is off by default and why bringing your own secret stays the
supported path.

```yaml
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

This targets the IPsec requirements for the F1 interface. It is not a compliance statement,
and it claims nothing about any CNI beyond the requirements listed above.

## Limits

- **O1 and IPsec cannot be combined.** In O1 mode the config comes from the datastore at
  runtime, so the chart cannot check that the application binds to the protected addresses,
  and the O1 interface could move it off them afterwards.
- **N3 is protected only with `ipsec.protectN3`.** It needs a peer on the core side (UPF)
  that terminates IKEv2 with a certificate from the same authority. Without the flag, the
  policy keeps its plaintext rule for the core and the chart makes no claim about that
  interface. With it, `cu_up.ngu.socket[].bind_addr` must name the protected addresses, the
  entrypoint no longer binds N3 to the pod address, and the core is allowed the tunnel
  only.
- **A kernel-bypass datapath is not protected.** Traffic that never reaches the kernel
  network stack never reaches XFRM either. This applies to F1-U carried over a bypass
  datapath, not to E1.
