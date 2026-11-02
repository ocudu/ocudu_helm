# Hugepages

**Applies to:** `ocudu-gnb`, `ocudu-du`.

The DPDK Open Fronthaul datapath needs hugepages. `ocudu-gnb` and a DPDK/OFH-configured
`ocudu-du` configure the hugepage volume automatically from their `resources`: name
`hugepages-1Gi` or `hugepages-2Mi` under `resources`, and the chart creates and mounts the
matching volume. The CU-side charts (`ocudu-cu`, `ocudu-cu-cp`, `ocudu-cu-up`) have no
DPDK datapath and ignore hugepages.

> **`ocudu-du` does not need hugepages by default.** Its shipped config is an SDR radio over
> UHD (`ru_sdr`, `device_driver: uhd`), which uses no hugepages. A DU needs them only when
> configured for DPDK Open Fronthaul (a `ru_ofh` + `hal` section). See
> [SR-IOV setup → Scope](sriov-setup.md#scope-which-du-deployments-need-this). `ocudu-gnb`
> always runs the DPDK datapath and always needs them.

Hugepages are a node resource: they have to be reserved on the node first, or a pod that
requests them stays `Pending`.

## Jump to

| If you want to… | Go to |
|---|---|
| check the node has hugepages | [Checking node support](#checking-node-support) |
| reserve hugepages on the node | [Reserving hugepages on the node](#reserving-hugepages-on-the-node) |
| turn hugepages on in the chart | [Requesting hugepages in the chart](#requesting-hugepages-in-the-chart) |
| understand what the chart does with them | [How the chart handles them](#how-the-chart-handles-them) |
| size the reservation | [How much to reserve](#how-much-to-reserve) |
| fix a Pending pod | [Troubleshooting](#troubleshooting) |

## Checking node support

```bash
# Capacity advertised by each node
kubectl get nodes -o json | jq '.items[].status.capacity | {h1g: .["hugepages-1Gi"], h2m: .["hugepages-2Mi"]}'

# On the node itself
grep -i huge /proc/meminfo
```

## Reserving hugepages on the node

If the node has none, reserve them. 1Gi pages are recommended for DPDK.

```bash
# Reserve 8 x 1Gi pages
echo 8 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages

# Or 4096 x 2Mi pages (8Gi total)
echo 4096 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
```

1Gi pages must usually be reserved at boot, via the kernel command line
(`default_hugepagesz=1G hugepagesz=1G hugepages=8`), because the node may not have enough
contiguous memory to allocate them later. After changing the node, restart the kubelet or
the node so it re-reads hugepage capacity.

## Requesting hugepages in the chart

Add `hugepages-1Gi` (or `hugepages-2Mi`) under `resources`. Kubernetes requires the
hugepage limit and request to be equal, so set both:

```yaml
# chart: ocudu-gnb
resources:
  limits:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
  requests:
    cpu: 12
    memory: 16Gi
    hugepages-1Gi: 2Gi
```

2Mi pages instead of 1Gi (a DPDK/OFH-configured DU):

```yaml
# chart: ocudu-du   (DPDK Open Fronthaul mode — ru_ofh + hal configured)
resources:
  limits:
    cpu: 12
    memory: 16Gi
    hugepages-2Mi: 1Gi
  requests:
    cpu: 12
    memory: 16Gi
    hugepages-2Mi: 1Gi
```

Leave hugepages out of `resources` and the chart creates no hugepage volume. This is the
right configuration for the **default SDR/UHD DU**, which uses no DPDK datapath:

```yaml
# chart: ocudu-du   (default SDR/UHD mode — no hugepages needed)
resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

## How the chart handles them

When `hugepages-1Gi` or `hugepages-2Mi` appears under `resources.limits` **or**
`resources.requests`, the chart:

1. creates an `emptyDir` volume with `medium: HugePages-1Gi` or `medium: HugePages-2Mi`;
2. mounts it at `/hugepages-1Gi` or `/hugepages-2Mi` in the application container.

There is no separate flag — the presence of the resource key is the switch. Use only one
page size per pod; naming both creates both volumes.

## How much to reserve

For a DPDK workload, 1Gi pages are recommended. A rough starting point is 2–8 Gi of 1Gi
pages, sized for the DPDK mempool and packet buffers plus a margin. Reserve at least as
much on the node as the pod requests, with room for any other hugepage users on that node.

## Troubleshooting

**Pod Pending with "Insufficient hugepages-1Gi"** — the pod requests hugepages the node
does not have. Either reserve them (see above) or remove the key from `resources`.

```bash
kubectl describe node <node-name> | grep -i hugepages
kubectl describe pod <pod-name> -n <namespace>
```

**Confirm hugepages inside the pod**

```bash
kubectl exec <pod-name> -n <namespace> -- df -h | grep -i huge
kubectl exec <pod-name> -n <namespace> -- grep -i huge /proc/meminfo
```

## See also

- [SR-IOV setup](sriov-setup.md) — the other half of the DPDK datapath.
- [Network modes](network-modes.md) — when a chart uses the DPDK datapath.
- [Operations](operations.md) — resources, QoS and CPU pinning for DPDK pods.
- DPDK hugepage reference: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html#use-of-hugepages
