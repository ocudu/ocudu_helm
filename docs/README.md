# OCUDU RAN Documentation

Shared guides for the OCUDU RAN charts (`ocudu-gnb`, `ocudu-cu`, `ocudu-du`,
`ocudu-cu-cp`, `ocudu-cu-up`). Each guide explains one feature once, for every chart that
has it. Pair a guide with your chart's own README to configure a feature end to end.

New here? Start with [Which chart do I need?](../README.md#which-chart-do-i-need) in the
root README.

## Guides

| Guide | Covers |
|-------|--------|
| [IPsec](ipsec.md) | Encrypting the interfaces between RAN nodes with the IPsec sidecar |
| [O1](o1.md) | O1/NETCONF management via `values-o1.yaml`: TLS, SSH host key, users |
| [Security](security.md) | Pod Security Standards, Linux capabilities per binary, service account |
| [Operations](operations.md) | Resources and QoS, upgrades, probes, PodDisruptionBudget, init process |
| [Storage](storage.md) | Persistence (emptyDir, PVC, hostPath) and log files |
| [Network modes](network-modes.md) | CNI vs hostNetwork vs SR-IOV, and which chart supports which |
| [NetworkPolicy](networkpolicy.md) | How the NetworkPolicy is built and its per-chart peers |
| [SR-IOV setup](sriov-setup.md) | Preparing SR-IOV on the node and in the cluster |
| [Hugepages](hugepages.md) | Hugepages for DPDK |

> These guides are being written and added over time. Each becomes a link here once its
> page exists. Until then, the information lives in the relevant chart's README.

## Feature matrix

Which RAN chart supports which feature. Verified against each chart's `values.yaml` and
`values-o1.yaml`.

| Feature | ocudu-gnb | ocudu-cu | ocudu-du | ocudu-cu-cp | ocudu-cu-up |
|---------|:---------:|:--------:|:--------:|:-----------:|:-----------:|
| IPsec | ✅ | ✅ | ✅ | ✅ | ✅ |
| O1 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Security context / capabilities | ✅ | ✅ | ✅ | ✅ | ✅ |
| Resources, QoS, upgrades, probes | ✅ | ✅ | ✅ | ✅ | ✅ |
| PodDisruptionBudget | ✅ | ✅ | ✅ | ✅ | ✅ |
| Init process (`initCommand`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Persistence | ✅ | ✅ | ✅ | ✅ | ✅ |
| CNI networking | ✅ | ✅ | ✅ | ✅ | ✅ |
| hostNetwork | ✅ | ✅ | ✅ | ✅ | ✅ |
| NetworkPolicy | ✅ | ✅ | ✅ | ✅ | ✅ |
| SR-IOV | ✅ | ❌ | ✅ | ❌ | ❌ |
| Hugepages / DPDK | ✅ | ❌ | ✅ | ❌ | ❌ |

### Interfaces per chart

The 3GPP interfaces each chart terminates with a Kubernetes Service. All five can also expose
an O1 and a metrics service.

| Chart | N2 | N3 | E1 | F1-C | F1-U | Notes |
|-------|:--:|:--:|:--:|:----:|:----:|-------|
| ocudu-gnb | ⚪ | ⚪ | — | — | — | CU and DU in one pod; F1 is internal. Optional N2/N3 Service via `service.enabled` (off by default) |
| ocudu-cu | ✅ | ✅ | — | ✅ | ✅ | Full CU; F1 to a separate DU |
| ocudu-du | — | — | — | ✅ | ✅ | F1 to a separate CU |
| ocudu-cu-cp | ✅ | — | ⚪ | ✅ | — | Control plane; E1 to CU-UP, F1-C to DU |
| ocudu-cu-up | — | ✅ | ⚪ | — | ✅ | User plane; E1 to CU-CP, F1-U to DU |

Legend: ✅ terminated by this chart, ⚪ optional (off by default), — not applicable.

### Xn

Xn is not terminated through a Service; it is an optional NetworkPolicy peer rule, off by
default. Support per chart (Xn-C is control signalling, Xn-U is user-plane data):

| Chart | Xn-C | Xn-U | Why |
|-------|:----:|:----:|-----|
| ocudu-gnb | ✅ | ✅ | full node: both control and user plane |
| ocudu-cu | ✅ | ✅ | full CU: both planes |
| ocudu-cu-up | — | ✅ | user plane, so Xn-U only |
| ocudu-cu-cp | ✅ | — | control plane only, so no Xn-U |
| ocudu-du | — | — | DU has no Xn peer; it talks F1 to the CU |

## Notes on the matrix

- **SR-IOV and hugepages/DPDK** apply to the charts that carry user-plane fronthaul traffic
  (`ocudu-gnb` and `ocudu-du`, which run the DPDK images). The CU-side charts
  (`ocudu-cu`, `ocudu-cu-cp`, `ocudu-cu-up`) do not define an SR-IOV or hugepages
  configuration.
- **NetworkPolicy** is only effective when `network.hostNetwork` is `false`.
- **Xn** is the node-to-node interface (gNB-to-gNB or across a split CU). It is not
  terminated with a Service; see the [Xn](#xn) section above for per-chart support.
