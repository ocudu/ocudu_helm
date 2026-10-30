# Network modes

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Every RAN chart runs in one of two network modes, set by `network.hostNetwork`:

- **CNI (`network.hostNetwork: false`, the default)** — the pod gets its own network
  namespace from the cluster CNI. [NetworkPolicy](networkpolicy.md) is available here (when
  enabled and backed by a policy-capable CNI), and the pod can take a dedicated interface
  from an SR-IOV device plugin.
- **host network (`network.hostNetwork: true`)** — the pod shares the node's network
  namespace. Simple to set up, but NetworkPolicy has no effect and the pod sees the node's
  interfaces directly.

All five charts default to CNI (`network.hostNetwork: false`).

| Mode | NetworkPolicy | Isolation | SR-IOV | Typical use |
|------|:-------------:|:---------:|:------:|-------------|
| CNI (`hostNetwork: false`) | available when enabled + CNI supports it | per-pod namespace | available where the chart supports it | production, multi-tenant, traffic control |
| host network (`hostNetwork: true`) | no effect | shares the node | not used | quick bring-up on bare metal, development |

## Jump to

| If you want to… | Go to |
|---|---|
| run the production default (CNI) | [CNI mode (default)](#cni-mode-default) |
| bring a pod up quickly on bare metal | [Host network mode](#host-network-mode) |
| give a pod a dedicated SR-IOV interface | [SR-IOV](#sr-iov) |
| decide which mode to use | [Choosing a mode](#choosing-a-mode) |

## CNI mode (default)

The pod is on the cluster pod network. This is the mode to use in production: it is the
only mode where [NetworkPolicy](networkpolicy.md) restricts traffic, and it keeps each pod
in its own network namespace.

```yaml
# chart: ocudu-cu
network:
  hostNetwork: false
networkPolicy:
  enabled: true
```

## Host network mode

The pod uses the node's network namespace. Use it only where CNI is not an option — for
example a bare-metal bring-up before the fabric is ready.

```yaml
# chart: ocudu-cu
network:
  hostNetwork: true
```

Consequences of `hostNetwork: true`, all enforced by the chart or by Kubernetes:

- **NetworkPolicy is ignored.** The chart does not even render the policy when
  `hostNetwork` is `true`; see [NetworkPolicy](networkpolicy.md).
- **IPsec is refused.** The IPsec sidecar requires `network.hostNetwork: false`; see
  [IPsec](ipsec.md).
- **On the DPDK charts (`ocudu-gnb`, `ocudu-du`) you must also turn SR-IOV off.** Both
  charts default `sriovConfig.enabled: true`, and the SR-IOV extended-resource request is
  gated only on `sriovConfig.enabled` — setting `network.hostNetwork: true` does **not**
  remove it. Leave it on and the pod still asks for the device-plugin resource and stays
  `Pending` on any node that does not advertise it. Set `sriovConfig.enabled: false` for a
  host-network bring-up.
- **The DPDK charts also need a privileged container here.** Without the SR-IOV device
  plugin the datapath needs `privileged: true` and `NET_ADMIN`; this is the host-network
  fallback described in the Security guide's
  [Host-network fallback (DPDK charts)](security.md#host-network-fallback-dpdk-charts)
  section. It is far less isolated than the default and is a last resort.
- **O1 on a privileged port needs node help *and* a values override.** `values-o1.yaml`
  puts `podSecurityContext.sysctls: [net.ipv4.ip_unprivileged_port_start]` in the pod spec,
  and Kubernetes **rejects any `net.*` sysctl on a host-network pod** — so the pod fails to
  admit until you clear it (`podSecurityContext.sysctls: []`). With that removed, the
  non-root NETCONF server can bind port 830 only if the node's own
  `net.ipv4.ip_unprivileged_port_start` already allows it. See [O1](o1.md).

```yaml
# chart: ocudu-gnb — host-network bring-up on a DPDK chart
network:
  hostNetwork: true
sriovConfig:
  enabled: false        # the SR-IOV request is not removed by hostNetwork alone
securityContext:
  privileged: true      # host-network fallback for the DPDK datapath
  capabilities:
    add:
      - SYS_NICE
      - NET_ADMIN
# With O1 (values-o1.yaml) also clear the rejected net.* sysctl:
# podSecurityContext:
#   sysctls: []
```

## SR-IOV

In CNI mode a chart that runs user-plane fronthaul can take a dedicated SR-IOV virtual
function instead of sharing the pod network, through the SR-IOV device plugin. Only the
charts that carry that traffic define an `sriovConfig`:

| Chart | `sriovConfig` | Default `extendedResourceName` |
|-------|:-------------:|--------------------------------|
| ocudu-gnb | ✅ | `intel.com/intel_sriov_netdevice` |
| ocudu-du | ✅ | `intel.com/intel_sriov_dpdk` |
| ocudu-cu | ❌ | — |
| ocudu-cu-cp | ❌ | — |
| ocudu-cu-up | ❌ | — |

The CU-side charts (`ocudu-cu`, `ocudu-cu-cp`, `ocudu-cu-up`) do not define an
`sriovConfig`: they do not carry fronthaul user-plane traffic, so there is nothing to
offload to a VF.

`sriovConfig.enabled` defaults to `true` on the charts that have it, and must be `true`
whenever `network.hostNetwork` is `false`. The `extendedResourceName` must match a resource
your SR-IOV device plugin advertises; when `sriovConfig.enabled` is `true` the chart adds
that request to `resources.limits` and `resources.requests` for you, so do not list the
extended resource under `resources` yourself (set only `cpu` and `memory`).

```yaml
# chart: ocudu-gnb
network:
  hostNetwork: false
sriovConfig:
  enabled: true
  extendedResourceName: "intel.com/intel_sriov_netdevice"
resources:
  limits:
    cpu: 4
    memory: 4Gi
  requests:
    cpu: 4
    memory: 4Gi
```

On `ocudu-du` the device plugin resource is DPDK-bound. `intel.com/intel_sriov_netdevice`
(the kernel netdev driver) is **not** supported for the DU; use a DPDK resource such as
`intel.com/intel_sriov_dpdk`:

```yaml
# chart: ocudu-du
network:
  hostNetwork: false
sriovConfig:
  enabled: true
  extendedResourceName: "intel.com/intel_sriov_dpdk"
resources:
  limits:
    cpu: 4
    memory: 4Gi
  requests:
    cpu: 4
    memory: 4Gi
```

Preparing the node and the cluster for SR-IOV — the device plugin, VFs, and drivers — is
covered in [SR-IOV setup](sriov-setup.md). DPDK also needs hugepages; see
[Hugepages](hugepages.md).

## Choosing a mode

- Use **CNI mode** by default. It is the only mode where NetworkPolicy and IPsec work, and
  it is required for production and multi-tenant clusters.
- Use **host network mode** only for a quick bring-up or development on bare metal where
  CNI is not yet available, and accept that NetworkPolicy and IPsec are off.

## See also

- [NetworkPolicy](networkpolicy.md) — how the per-pod policy is built and its peers.
- [SR-IOV setup](sriov-setup.md) — preparing SR-IOV on the node and in the cluster.
- [Hugepages](hugepages.md) — hugepages for DPDK.
- [IPsec](ipsec.md) — requires CNI mode.
- [O1](o1.md) — the `hostNetwork` caveat for port 830.
