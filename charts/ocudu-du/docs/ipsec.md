# IPsec for F1

The DU chart can run a strongSwan sidecar that protects the F1 interfaces with IKEv2 and
tunnel-mode ESP. It is off by default and changes nothing until `ipsec.enabled` is set.

The model is one pod, one network namespace, one daemon, and one child association per
protected interface. Because every pod has its own network namespace, the DU and the CU
stay separate tunnel endpoints even when the scheduler puts them on the same node.

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
DU pod                                        CU pod
  ipsec-f1c  100.64.10.2                        ipsec-f1c  100.64.10.1
  ipsec-f1u  100.64.30.2                        ipsec-f1u  100.64.30.1
        \                                             /
         eth0 <pod address>  ==ESP in UDP==>  eth0 <pod address>
```

The inner addresses come from `ipsec.protectedSupernet` and are yours to choose. They exist
only inside the two pods. The outer addresses are the pod addresses, which is why the peer
is named by a headless service: its record resolves straight to the pod address, and the
name is resolved again on every attempt, so a rescheduled peer is found at its new address.
A cluster IP service cannot carry this traffic — it forwards only the ports it declares and
it rewrites addresses.

`ifId` is a local number. Nothing about it is negotiated or sent, so the two ends need not
agree on it, but it has to be unique inside the pod and must not be 0.

## Configuring it

### 1. The credentials

Create a secret holding `tls.crt`, `tls.key` and `ca.crt`, and name it in
`ipsec.certSecret`. The two ends need certificates from the same certificate authority, and
each end's `localId` has to match a subject alternative name of its own certificate.

```bash
kubectl create secret generic ocudu-du-ipsec \
  --from-file=tls.crt=du.crt --from-file=tls.key=du.key --from-file=ca.crt=ca.crt
```

Anything that produces those three files works. `ipsec.certManager` can issue them instead,
if cert-manager is installed — see below.

### 2. The values

Every peer this pod talks to is an entry under `ipsec.peers`, and every protected
interface is an entry under `ipsec.connections` naming the peer that carries it. One side
sets that peer's `address` and starts the connection; the other leaves it empty and waits.
Either side can be the one that starts. Below the DU starts, which suits it: it is the side
that opens F1 anyway.

With a single peer the `peer` key on a connection may be left out. It becomes required the
moment a second peer appears, because then which association carries an interface is a real
choice and guessing it wrong puts that interface on an association whose peer identity is
not the one that owns it.

```yaml
# DU
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
      ifName: ipsec-f1c
      ifId: 257
      local: 100.64.10.2
      remote: 100.64.10.1
    f1u:
      peer: cu
      ifName: ipsec-f1u
      ifId: 258
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

The CU is the mirror image, with `peer.address` left empty and `local` and `remote` the
other way round.

### 3. Point the application at the protected addresses

The chart does not rewrite the application config; it checks it. Every `local` address in
`ipsec.connections` has to appear in the `f1ap` and `f1u` sections of the config, and those
sections must not bind a wildcard address. A wildcard leaves the application listening on
the pod address as well, which is the path the tunnel exists to close, so the chart refuses
to render it.

`f1ap.addrs` is the CU's protected F1-C address, which is the same value as
`ipsec.connections.f1c.remote`. F1-U needs no peer address: the tunnel endpoints are
signalled inside F1AP, so binding the protected address is enough.

**F1-U must not use the core's GTP-U port.** The policy has to let the application reach the
core on UDP 2152, and a NetworkPolicy rule names a port and an address range, never a peer.
The peer's pod address is inside that range, so while F1-U uses 2152 that one rule also
permits plaintext F1-U straight to the peer, around the tunnel. The core's port is fixed;
F1-U's is not, so F1-U moves. Set the same port on both ends:

```yaml
f1u:
  bind_port: 2151
  peer_port: 2151
```

The chart refuses to render otherwise. Set `ipsec.allowF1uOnCorePort: true` if there is no
core to reach.

## What the chart refuses to render

Each of these stops `helm install` with a message explaining why. None of them is a
warning, because a silent fall back to unprotected traffic is the one outcome this feature
exists to prevent.

| Refused | Why |
|---|---|
| `network.hostNetwork: true` | the pod is not a separate endpoint |
| `o1.enable_ocudu_o1: true` | in O1 mode the config is written at runtime, so it cannot be checked, and it can be changed again later |
| Kubernetes older than 1.29 | no sidecar init containers, so no ordering guarantee |
| `f1cService` or `f1uService` enabled | they publish an unprotected path on the pod address |
| `networkPolicy.enabled: false` | the application could still address the peer directly; override with `ipsec.allowWithoutNetworkPolicy` only where unprotected traffic is blocked some other way |
| an empty `ipsec.connections` | a sidecar protecting nothing |
| a duplicate or zero `ifId`, a duplicate or over-long `ifName` | two children sharing one tunnel, or no tunnel at all |
| a missing `certSecret`, `localId` or `peers.<name>.id` | without a peer identity any certificate the authority signed would be accepted, from anyone |
| an empty `ipsec.peers`, or a peer no connection names | the daemon would hold an association that protects nothing and report itself ready for it |
| a connection naming a peer that is not in `ipsec.peers`, or naming none while there is more than one | the interface would land on the wrong association, or on none |
| `ipsec.encapsulation` set to anything but `udp` or `native` | there is no third way to carry ESP, and a typo would otherwise pick the default silently |
| an F1 address in the config that is not in `ipsec.connections`, or a wildcard bind | traffic that would never enter the tunnel |
| F1-U on the core's GTP-U port, 2152 | the policy rule that lets the core be reached also permits plaintext F1-U to the peer; override with `ipsec.allowF1uOnCorePort` |

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
- **This protects F1 and nothing else.** The fronthaul is a separate interface with its own
  requirements, and a kernel-bypass datapath does not pass through XFRM at all. F1-C and
  F1-U go through the kernel network stack, which is why they can be protected this way.
