# NetworkPolicy

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Each chart can render a Kubernetes `NetworkPolicy` that restricts the pod to the traffic
it actually needs. It is off by default (`networkPolicy.enabled: false`).

**NetworkPolicy only works in CNI mode.** The chart renders the policy only when
`networkPolicy.enabled` is `true` **and** `network.hostNetwork` is `false`. With
`hostNetwork: true` the pod shares the node's network namespace and bypasses
NetworkPolicy, so the chart does not render it at all. See
[Network modes](network-modes.md).

A NetworkPolicy also needs a controller in the cluster (Calico, Cilium, Antrea, Weave Net,
...). Without one the object exists but nothing enforces it.

## Jump to

| If you want to… | Go to |
|---|---|
| understand how the rules are assembled | [How the policy is built](#how-the-policy-is-built) |
| find your chart's peer keys | [Peer keys per chart](#peer-keys-per-chart) |
| see which ports each interface opens | [Default ports](#default-ports) |
| turn the policy on and point it at your core | [Enabling the policy](#enabling-the-policy) |
| allow an Xn peer | [Xn](#xn) |
| fix name lookups failing once the policy is on | [DNS](#dns) |
| know what changes when IPsec is on | [IPsec and the policy](#ipsec-and-the-policy) |
| add rules the named keys do not cover | [Custom rules](#custom-rules) |
| work out why traffic is blocked | [Debugging](#debugging) |

## How the policy is built

The policy selects this chart's pod and sets both `Ingress` and `Egress`. Each rule comes
from a named key under `networkPolicy.ingress` and `networkPolicy.egress`. A key has an
`enabled` flag and a list of peers (`from` for ingress, `to` for egress); the chart fixes
the ports for that peer from the interface it represents. You supply the peers; you do not
set the ports.

Peers are named by pod label where the peer is another chart in the same namespace (for
example `app.kubernetes.io/name: ocudu-du`), and by `ipBlock` for something outside the
cluster such as the 5G core. A CIDR is not a reliable way to name an in-cluster pod: some
CNIs do not apply CIDR rules to cluster-internal addresses, so such a rule can silently
match nothing.

Two egress rules are always present when the policy renders:

- **DNS** — UDP and TCP port 53, to the peers in `egress.dnsTo` (see
  [DNS](#dns) below).
- Each `enabled` peer key contributes its own rule.

Within this policy, traffic not matched by a rule is denied: selecting the pod for
`Ingress`/`Egress` switches it from allow-all to allow-only-what-is-listed. Two caveats
keep this from being absolute isolation, both standard Kubernetes NetworkPolicy behaviour:

- **Policies are additive.** Another NetworkPolicy that selects the same pod can *add*
  allowed traffic; policies never subtract from each other. This chart's policy restricts
  what it covers, but it cannot guarantee nothing else in the namespace opens more.
- **Traffic from the pod's own node is treated specially.** Depending on the CNI, packets
  from the local node (for example kubelet health probes) may reach the pod regardless of
  ingress rules.

See the [Kubernetes NetworkPolicy docs](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
for the exact semantics.

## Peer keys per chart

The peer keys differ by chart, because each chart terminates different interfaces. Most
keys exist under **both** `ingress` and `egress`, but two do not: `management` is
**ingress-only** (on `ocudu-gnb`), and `dnsTo` is **egress-only** (all charts). The table
below marks those. `ric` is **egress-only** too, since the E2 agent always dials the RIC.

| Key | gnb | cu | du | cu-cp | cu-up | Peer / interface |
|-----|:---:|:--:|:--:|:-----:|:-----:|------------------|
| `fiveGCore` | ✅ | ✅ | — | ✅ | ✅ | 5G core (N2/NGAP, N3/GTP-U) |
| `du` | — | ✅ | — | ✅ | ✅ | the DU over F1 |
| `cu` | — | — | ✅ | — | — | the CU over F1 (names `ocudu-cu`, `ocudu-cu-cp`, `ocudu-cu-up`) |
| `cuUp` | — | — | — | ✅ | — | the CU-UP over E1 (E1AP) |
| `cuCp` | — | — | — | — | ✅ | the CU-CP over E1 (E1AP) |
| `xn` | ✅ | ✅ | — | ✅ | ✅ | an Xn peer (see [Xn](#xn)) |
| `management` | ✅ | — | — | — | — | O1/NETCONF management (ingress only) |
| `egress.ric` | ✅ | ✅ | ✅ | ✅ | ✅ | the near-RT RIC over E2 (egress only, off by default) |
| `monitoring` | ✅ | ✅ | ✅ | ✅ | ✅ | metrics scrape / metrics push |
| `custom` | ✅ | ✅ | ✅ | ✅ | ✅ | your own extra rules |
| `egress.dnsTo` | ✅ | ✅ | ✅ | ✅ | ✅ | cluster DNS (egress only) |

Legend: ✅ the key exists on that chart, — it does not.

Notes on the differences:

- `fiveGCore` opens only the interfaces that chart terminates: `ocudu-cu-cp` opens N2
  (SCTP 38412) only, `ocudu-cu-up` opens N3 (UDP 2152) only, and `ocudu-gnb`/`ocudu-cu`
  open both.
- The DU has no `fiveGCore` and no `xn`: it talks F1 to the CU and nothing else. Its one
  interface peer is `cu`, which names all three CU charts because a DU peers with either a
  combined CU or a CU-CP plus CU-UP, and the chart cannot know which.
- `management` exists only on `ocudu-gnb`. Its rule renders only when
  `o1.enable_ocudu_o1` is `true`, on TCP `o1.o1Port` (default 830). On the other charts,
  reach the O1 service through a `custom` rule.
- `monitoring` is gated differently per direction. The **ingress** rule (a scraper
  reaching the metrics port) renders only when `metricsService.enabled` **and**
  `networkPolicy.ingress.monitoring.enabled` are both `true`, and opens
  `metricsService.port` (TCP 8001 by default). The **egress** rule (the pod pushing metrics
  out) is gated only on `networkPolicy.egress.monitoring.enabled`, which defaults to
  `true` — so it renders by default **even when the metrics Service is disabled**.

## Default ports

With the default peer keys enabled and IPsec off, the policy opens these ports. For the
3GPP interfaces the chart fixes the port from the interface the key represents; you do not
configure it. The DNS and monitoring rows are supporting egress, not interfaces: their
ports are fixed the same way, but their destinations are configurable (`egress.dnsTo`, and
the monitoring peer).

| Traffic | Protocol / port | On which charts |
|---------|-----------------|-----------------|
| N2 (NGAP) | SCTP 38412 | gnb, cu, cu-cp |
| N3 (GTP-U) | UDP 2152 | gnb, cu, cu-up |
| F1-C (F1AP) | SCTP 38472 | cu, du, cu-cp |
| F1-U (GTP-U) | UDP 2152 egress; UDP 2151 (container port) on `cu`/`cu-up` ingress, 2152 on `du` ingress | cu, du, cu-up |
| E1 (E1AP) | SCTP 38462 | cu-cp, cu-up |
| Xn-C (XnAP) | SCTP 38422 | gnb, cu, cu-cp |
| Xn-U (GTP-U) | UDP `xn.xnuPort` (default 2152) | gnb, cu, cu-up |
| E2 (E2AP) | SCTP `egress.ric.port` (default 36421) — only when `egress.ric.enabled` | all |
| DNS | UDP/TCP 53 | all |
| Monitoring (ingress scrape) | TCP `metricsService.port` (8001) — only when `metricsService.enabled` | all |
| Monitoring (egress push) | TCP 8086 (InfluxDB); TCP 8443 (VES, gnb with O1) | all |

The F1-U ingress port differs because `cu` and `cu-up` accept F1-U on the GTP-U container
port (`f1uService.targetPort`, 2151), while `du` uses the service port (2152). You do not
set these; the chart takes them from its own F1-U Service.

## Enabling the policy

Turn the policy on in CNI mode. The default peer keys cover the normal interfaces, so for
many deployments enabling it is enough:

```yaml
# chart: ocudu-du
network:
  hostNetwork: false
networkPolicy:
  enabled: true
```

Point a peer at your actual core network instead of the wide default CIDR:

```yaml
# chart: ocudu-cu
networkPolicy:
  enabled: true
  ingress:
    fiveGCore:
      enabled: true
      from:
        - ipBlock:
            cidr: 10.0.0.100/32   # the AMF/UPF address
  egress:
    fiveGCore:
      enabled: true
      to:
        - ipBlock:
            cidr: 10.0.0.0/24     # the core network
```

## Xn

The `xn` key allows an Xn peer (another gNB, or across a split CU) in the same namespace.
It is off by default, because a rule for a peer that does not exist just opens a port for
nothing. When enabled it opens the Xn interfaces that chart carries: Xn-C (SCTP 38422) on
the control-plane-bearing charts, and Xn-U (UDP `xn.xnuPort`, default 2152) on the
user-plane-bearing charts.

- `ocudu-gnb` and `ocudu-cu` carry both planes: Xn-C and Xn-U.
- `ocudu-cu-cp` is control plane only: Xn-C, and its `xn` key has no `xnuPort`.
- `ocudu-cu-up` is user plane only: Xn-U, through `xn.xnuPort`.
- `ocudu-du` has no `xn` key at all; it peers with the CU over F1, not over Xn.

> **The default Xn selectors do not cover the gNB ↔ combined-CU (`ocudu-cu`) case.** On
> `ocudu-gnb`, the default `networkPolicy.ingress.xn.from` and `egress.xn.to` select
> `ocudu-gnb`, `ocudu-cu-cp` and `ocudu-cu-up` — **not** `ocudu-cu`. So enabling `xn` on a
> gNB and a combined CU does not produce working bidirectional rules until you override the
> gNB's selectors to name `ocudu-cu` (shown below). The combined-CU side already names the
> gNB by default.

```yaml
# chart: ocudu-gnb — add the combined CU as an Xn peer (the default selectors omit it)
networkPolicy:
  enabled: true
  ingress:
    xn:
      enabled: true
      from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ocudu-cu
  egress:
    xn:
      enabled: true
      to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ocudu-cu
```

```yaml
# chart: ocudu-cu-up
networkPolicy:
  enabled: true
  ingress:
    xn:
      enabled: true
      xnuPort: 2152
      from:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ocudu-gnb
  egress:
    xn:
      enabled: true
      xnuPort: 2152
      to:
        - podSelector:
            matchLabels:
              app.kubernetes.io/name: ocudu-gnb
```

## DNS

`egress.dnsTo` names where cluster DNS lives; the port 53 rule is always present. The
default names the cluster DNS pods (`k8s-app: kube-dns`), which works on a CNI that
translates a Service address before it applies policy. Some CNIs apply policy to the
Service address itself; there the default matches nothing, every lookup fails, and
anything that resolves a name at startup never starts. Set `dnsTo` to `[]` to allow port
53 to any destination instead — wider on destination, still only port 53:

```yaml
# chart: ocudu-gnb
networkPolicy:
  enabled: true
  egress:
    dnsTo: []
```

## IPsec and the policy

When [IPsec](ipsec.md) protects an interface, what the policy does depends on
`ipsec.encapsulation`:

- **`udp` (the default)** — the policy drops that interface's plaintext port and allows the
  IKE ports instead (UDP 4500, and UDP 500 unless `ipsec.ikeOnNatTPortOnly` is set), so the
  peer is allowed the tunnel and nothing else.
- **`native` (ESP, IP protocol 50)** — a Kubernetes NetworkPolicy can only name TCP, UDP
  and SCTP, **not** IP protocol 50, so the chart omits the `ports` field entirely on that
  rule. That permits **all** TCP, UDP and SCTP ports to the selected peer — including the
  plaintext interface ports this feature exists to close — and handling of other protocols
  is CNI-dependent. The confidentiality still comes from ESP on the wire; the policy just
  cannot narrow the peer to the tunnel. This is the cost of `native`, and the reason `udp`
  is the default. The chart's template says as much inline.

You do not configure the policy change itself; it follows from the IPsec settings. Which
key this affects, and what turns it on, differs by interface:

- **F1, E1 and Xn** (`du`, `cu`, `cuUp`, `cuCp`, `xn`) switch to the IKE ports whenever
  `ipsec.enabled` is `true`.
- **N2 and N3** (`fiveGCore`) switch only when the matching `ipsec.protectN2` or
  `ipsec.protectN3` is also set — both default to `false`, so `ipsec.enabled` on its own
  leaves the plaintext N2 (SCTP 38412) and N3 (UDP 2152) ports open. These keys exist on
  `ocudu-cu` (N2 and N3), `ocudu-cu-cp` (N2) and `ocudu-cu-up` (N3). On `ocudu-gnb` the
  `fiveGCore` ports are never swapped — the gNB chart has no `protectN2`/`protectN3` and
  its only IPsec-gated block for a 3GPP interface is `xn`.
- **E2** (`egress.ric`) switches only when `ipsec.protectE2` is also set. It defaults to
  `false`, so without it an enabled `egress.ric` opens plaintext SCTP 36421. Every chart
  has this key.

Leave the relevant peer key enabled either way, so its peer is still named.

## Custom rules

Add rules the named keys do not cover — a sidecar scraper, an external API, the O1 service
on a chart without a `management` key — through `ingress.custom` and `egress.custom`. Each
entry is a raw NetworkPolicy rule:

```yaml
# chart: ocudu-cu
networkPolicy:
  enabled: true
  ingress:
    custom:
      - from:
          - podSelector:
              matchLabels:
                app: debug-tool
        ports:
          - protocol: TCP
            port: 9090
  egress:
    custom:
      - to:
          - ipBlock:
              cidr: 192.168.1.0/24
        ports:
          - protocol: TCP
            port: 443
```

## Debugging

```bash
# Is the policy there? (nothing renders in hostNetwork mode)
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <release-name> -n <namespace>

# Does the cluster support the API, and is a controller running?
kubectl api-versions | grep networking.k8s.io/v1
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave|antrea'

# Test a port from another pod.
# Match the tool to the protocol: busybox `nc` only tests TCP, so it will report
# failure against an SCTP port (38412 N2, 38472 F1-C, 38462 E1, 38422 Xn-C) even when
# the traffic is allowed. Use an SCTP-capable tool for those.
kubectl run test --rm -it --image=busybox -- sh
#   nc -zv -u <pod-ip> 2152          # UDP port (GTP-U) — add -u
#   nc -zv    <pod-ip> 8001          # TCP port (metrics) — busybox nc is fine here
# For SCTP, use a tool that speaks it (nmap's ncat), not busybox nc:
#   ncat --sctp -z <pod-ip> 38412    # N2 (NGAP)
```

If a pod cannot resolve DNS once the policy is on, suspect `egress.dnsTo`; see
[DNS](#dns). If an interface is blocked, confirm its peer key is enabled and its peer is
named by a `podSelector` (for an in-cluster peer) rather than only a CIDR.

## See also

- [Network modes](network-modes.md) — CNI vs host network; NetworkPolicy needs CNI.
- [IPsec](ipsec.md) — how the policy changes for protected interfaces.
- [O1](o1.md) — the O1/NETCONF management interface.
