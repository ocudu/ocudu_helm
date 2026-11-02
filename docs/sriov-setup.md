# SR-IOV setup

**Applies to:** `ocudu-gnb`, `ocudu-du`.

SR-IOV (Single Root I/O Virtualization) gives a pod a dedicated network interface — a
Virtual Function (VF) — instead of sharing the pod network. `ocudu-gnb` and a DPDK/OFH-mode
`ocudu-du` use it for their Open Fronthaul user-plane traffic. The CU-side charts
(`ocudu-cu`, `ocudu-cu-cp`, `ocudu-cu-up`) do not carry that traffic and define no
`sriovConfig`.

**This applies only to a DPDK Open Fronthaul datapath.** `ocudu-du` ships with an
SDR/UHD radio by default (`ru_sdr`, `device_driver: uhd`), which uses no VF and no
hugepages. A DU needs SR-IOV (and the hugepages in the companion guide) only when it is
configured for Open Fronthaul with a DPDK `ru_ofh` + `hal` section. See
[Scope: which DU deployments need this](#scope-which-du-deployments-need-this).

SR-IOV is a property of the node and the cluster: the chart only *requests* a VF, through
`sriovConfig` and a matching entry under `resources`. This guide prepares the node and the
cluster so that request can be met. For how the chart requests the VF, see
[Network modes](network-modes.md#sr-iov).

## Jump to

| If you want to… | Go to |
|---|---|
| know whether your DU even needs this | [Scope: which DU deployments need this](#scope-which-du-deployments-need-this) |
| know what the node and cluster must provide | [Requirements](#requirements) |
| install the cluster components | [Cluster components](#cluster-components) |
| create VFs and bind a driver on the node | [Node setup](#node-setup) |
| find your chart's resource name | [Per-chart resource name](#per-chart-resource-name) |
| point the chart at the VF | [Configuring the chart](#configuring-the-chart) |
| confirm the VF reached the pod | [Verifying](#verifying) |
| fix a VF that never appears | [Troubleshooting](#troubleshooting) |

## Scope: which DU deployments need this

`ocudu-gnb` always runs the DPDK fronthaul datapath, so it always uses SR-IOV (and
hugepages) in CNI mode.

`ocudu-du` does **not**, by default. Although its default image is `du-dpdk`, its shipped
*configuration* uses an SDR radio over UHD (`ru_sdr`, `device_driver: uhd`), which needs **no
VF and no hugepages**. The DU entrypoint only writes a VF's PCI address into the config when
the config has a DPDK Open Fronthaul section:

- `ru_ofh` **+** `hal` present → DPDK: the entrypoint rewrites `network_interface` with the
  VF's PCI BDF and sets `du_mac_addr`. This is the mode that needs everything in this guide.
- `ru_ofh` **without** `hal` → the entrypoint treats it as a fatal misconfiguration.
- **no `ru_ofh`** (the default SDR DU) → SR-IOV substitution is skipped silently; the VF, if
  requested, is unused.

So treat the SR-IOV and hugepage requirements below as applying to **`ocudu-gnb` and a
DPDK/OFH-configured `ocudu-du`**. An SDR DU should set `sriovConfig.enabled: false` and omit
the hugepage keys — otherwise it holds a VF and hugepages it never uses.

## Requirements

Required for SR-IOV mode:

- A host whose NIC and firmware support SR-IOV, with VFs configured.
- **IOMMU enabled** in firmware and on the kernel command line (`intel_iommu=on
  iommu=pt`, or `amd_iommu=on iommu=pt`). `vfio-pci` needs a working IOMMU group per VF.
- **The `vfio-pci` module loaded** (`modprobe vfio-pci`) and the VFs bound to it (see
  [Node setup](#node-setup)).
- **Non-root device access.** Both charts run the application as uid 1000, so the VFIO
  device node must be openable by that uid:
  - the node's containerd must set
    `device_ownership_from_security_context = true`, or `/dev/vfio/<group>` is bind-mounted
    into the pod as `root:root 0600` and the uid-1000 process cannot open it (this requirement
    is documented in each chart's `values.yaml` comments, e.g.
    `charts/ocudu-gnb/values.yaml` and `charts/ocudu-du/values.yaml`);
  - and `/dev/vfio` permissions on the node must allow the mapped group access.
- **Lockable memory for DPDK DMA.** VFIO pins the DPDK hugepage memory, so the process needs
  either the `IPC_LOCK` capability or an unlimited `RLIMIT_MEMLOCK`. The DPDK charts carry
  `IPC_LOCK` by default; without enough lockable memory DPDK aborts with `EAL: Cannot set up
  DMA remapping, error 12 (Cannot allocate memory)`. See
  [Security](security.md#capabilities-per-chart) for the capability and ulimit details.
- VFs bound to a DPDK-compatible driver — **`vfio-pci` (recommended)**. `igb_uio` works
  but uses the UIO framework, which provides **no IOMMU isolation** and generally requires a
  **privileged/root** container — incompatible with these charts' non-root, unprivileged
  defaults. Use `vfio-pci` unless you have a specific reason not to, and expect to add the
  privileged security overrides from the [Security](security.md) guide if you insist on
  `igb_uio`.
- An **SR-IOV device plugin** advertising those VFs as an extended resource. This is the
  one cluster component these charts need for SR-IOV: they request the VF through the
  extended resource in `resources`, not through a `NetworkAttachmentDefinition`.
- The kubelet `static` CPU Manager policy **plus a Guaranteed pod** (see
  [Operations](operations.md#resources-and-qos)), so the DPDK container gets exclusive
  cores. The static policy alone is not enough — the pod must be Guaranteed and request
  whole CPUs; the DPDK images refuse to start if the CPU set they are given does not match
  their CPU request.

Multus CNI and the SR-IOV CNI plugin are **not** required by these charts. They belong to
the annotated-interface (`NetworkAttachmentDefinition`) workflow, which the charts do not
use — there is no `k8s.v1.cni.cncf.io/networks` annotation in the pod. Install them only
if something else in your cluster needs that path.

## Cluster components

The one component these charts need is the **SR-IOV device plugin**, which advertises VFs
as an extended resource (for example `intel.com/intel_sriov_dpdk`) — the name the chart's
`sriovConfig` and `resources` then use.

**Create and bind the VFs on the node *before* deploying the device plugin** (see
[Node setup](#node-setup)). The plugin discovers resources at startup and does not
automatically re-scan when the VF count or driver binding changes, so if you change VFs
after it is running you must restart its DaemonSet
(`kubectl rollout restart daemonset/kube-sriov-device-plugin -n kube-system`).

Pin the manifest to a specific release tag rather than `master`, so the installed component
cannot change out from under this procedure. The example below pins `v3.7.0` of
`sriov-network-device-plugin`; treat it as a pinned example and confirm the version against
your own environment before relying on it:

```bash
# SR-IOV device plugin (apply your ConfigMap first, naming the resource pool)
kubectl apply -f sriov-configmap.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/sriov-network-device-plugin/v3.7.0/deployments/sriovdp-daemonset.yaml
```

The ConfigMap is what maps VFs to the extended-resource names the chart requests, so you
must supply it — the upstream sample cannot be used unchanged. In particular, the upstream
`v3.7.0` sample defines `intel_sriov_netdevice` with **kernel** drivers (`i40evf`, `iavf`,
`ixgbevf`) and selects `vfio-pci` only under its separate `intel_sriov_dpdk` pool. These
charts drive the VF directly over DPDK, so **every pool the charts consume must select
`vfio-pci`** — including the gNB's `intel_sriov_netdevice`, despite its name. Applying the
upstream sample as-is recreates the kernel-netdevice / direct-DPDK mismatch. A ConfigMap that
backs both chart pools with `vfio-pci` VFs:

```yaml
# sriov-configmap.yaml — both pools select vfio-pci because the charts use DPDK directly.
apiVersion: v1
kind: ConfigMap
metadata:
  name: sriovdp-config
  namespace: kube-system
data:
  config.json: |
    {
      "resourceList": [
        {
          "resourceName": "intel_sriov_netdevice",
          "selectors": {
            "vendors": ["8086"],
            "devices": ["154c", "10ed"],
            "drivers": ["vfio-pci"],
            "pfNames": ["ens1f0"]
          }
        },
        {
          "resourceName": "intel_sriov_dpdk",
          "selectors": {
            "vendors": ["8086"],
            "devices": ["154c", "10ed"],
            "drivers": ["vfio-pci"],
            "pfNames": ["ens1f1"]
          }
        }
      ]
    }
```

> **`resourceName` is only the suffix.** The plugin advertises it under its resource prefix
> (default `intel.com`), so `"resourceName": "intel_sriov_netdevice"` becomes the
> `intel.com/intel_sriov_netdevice` the chart requests. Match the prefix+suffix to the
> `extendedResourceName` in your values, and set `vendors`/`devices`/`pfNames` to your own
> NIC — the `8086` vendor and `154c`/`10ed` device IDs and the `ens1f*` PF names above are
> examples. The gNB keeps the `intel_sriov_netdevice` name for historical reasons; if you
> would rather use the explicitly DPDK-named pool, point the gNB's
> `sriovConfig.extendedResourceName` at `intel.com/intel_sriov_dpdk` instead and drop the
> first pool.

You also need the kubelet `static` CPU Manager policy on nodes that run a DPDK pod, for
exclusive CPU pinning; see [Operations](operations.md#resources-and-qos).

Multus CNI and the SR-IOV CNI plugin are only for the `NetworkAttachmentDefinition`
workflow, which these charts do not use. If you need them for another workload, pin those
too (the tags below — Multus `v4.1.0`, SR-IOV CNI `v2.8.1` — are pinned examples, not
versions tested with these charts):

```bash
# Optional — only for the annotated-NAD approach, not used by these charts
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.1.0/deployments/multus-daemonset-thick.yml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/sriov-cni/v2.8.1/images/sriov-cni-daemonset.yaml
```

> These tags are pinned examples, chosen because they currently resolve — not versions
> validated against these charts. Before relying on them, test the combination in your
> environment and record the chart, Kubernetes and container-runtime versions you used
> alongside the chart version, so a manifest change is a visible, reviewed change.

## Node setup

Do this **before** deploying the device plugin (or restart the plugin's DaemonSet
afterwards — see [Cluster components](#cluster-components)). On each node that will run a
DPDK pod:

```bash
# 1. Identify the PF and its driver
lspci -nn | grep Ethernet
ethtool -i eth0 | grep driver

# 2. Load the VFIO driver (IOMMU must already be on — see Requirements)
modprobe vfio-pci

# 3. Create VFs on the chosen PF
echo 4 > /sys/class/net/eth0/device/sriov_numvfs

# 4. List the new VF PCI addresses (BDFs)
dpdk-devbind.py --status-dev net        # or: lspci | grep -i "Virtual Function"
```

Bind **each individual VF BDF** to `vfio-pci`. Writing a device ID to the driver's `new_id`
is not reliable: it registers an ID but does not unbind a VF already claimed by the kernel
driver, so bind explicitly per BDF and verify:

```bash
# Bind each VF BDF (repeat per VF; example BDFs shown)
dpdk-devbind.py --bind=vfio-pci 0000:3b:02.0 0000:3b:02.1

# Verify each one is now on vfio-pci
lspci -k -s 0000:3b:02.0      # "Kernel driver in use: vfio-pci"
```

**Persist across reboot.** The `sriov_numvfs` write and the driver binding above are
runtime-only and are lost on reboot. Make them permanent with your node's configuration
management — for example a systemd unit or a udev rule that recreates the VFs and re-binds
them to `vfio-pci` at boot, or your SR-IOV operator of choice. Re-running the manual steps
by hand after every reboot is not a supported production setup.

Confirm the device plugin now advertises the resource (restart its DaemonSet first if it
was already running when you changed the VFs):

```bash
kubectl get node <node-name> -o json | jq '.status.allocatable' | grep intel.com/intel_sriov
# e.g.  "intel.com/intel_sriov_dpdk": "4"
```

## Per-chart resource name

Each chart's `sriovConfig.extendedResourceName` must match a resource your device plugin
advertises. The defaults differ:

| Chart | `sriovConfig` | Default `extendedResourceName` | VF binding this guide supports |
|-------|:-------------:|--------------------------------|--------------------------------|
| ocudu-gnb | ✅ | `intel.com/intel_sriov_netdevice` | `vfio-pci` (DPDK) |
| ocudu-du | ✅ | `intel.com/intel_sriov_dpdk` | `vfio-pci` (DPDK) |
| ocudu-cu | ❌ | — | — |
| ocudu-cu-cp | ❌ | — | — |
| ocudu-cu-up | ❌ | — | — |

> **Both charts consume the VF directly through DPDK, so the VF must be bound to
> `vfio-pci`.** The entrypoint receives the VF's PCI address from the device plugin
> (`PCIDEVICE_<resource>`) and writes that bus address into the DPDK fronthaul config
> (`ru_ofh` → `network_interface`); it does **not** move a kernel network interface into the
> pod. A VF left on a kernel driver (`iavf`, `i40evf`) is not usable by these charts through
> the device-plugin-only path — requesting the extended resource alone does not attach a
> kernel netdev to the pod namespace, which would need Multus + the SR-IOV CNI and a
> `NetworkAttachmentDefinition` the charts do not use.
>
> The gNB default pool name is `intel.com/intel_sriov_netdevice` for historical reasons, but
> under this guide's device-plugin-only workflow it must point at a pool of **`vfio-pci`-bound**
> VFs (the same binding as the DU's `intel.com/intel_sriov_dpdk`). Name the pool whatever your
> device-plugin ConfigMap advertises; what matters is the VFs behind it are bound to
> `vfio-pci`.

`sriovConfig.enabled` defaults to `true` on both charts. On a chart that actually runs the
DPDK fronthaul datapath it must stay `true` when `network.hostNetwork` is `false` (the gNB's
`values.yaml` carries that note). An SDR-mode DU does not *use* a VF, but the chart still
**requests** one while the default `sriovConfig.enabled: true` remains set — the Deployment
template gates the extended-resource request only on `sriovConfig.enabled`, not on the
application config, so the VF is held and left unused. Set `sriovConfig.enabled: false` for
SDR/UHD deployments — see
[Scope: which DU deployments need this](#scope-which-du-deployments-need-this).

## Configuring the chart

Set `sriovConfig`. When `sriovConfig.enabled` is `true`, the chart adds the VF request to
both `resources.limits` and `resources.requests` for you, using
`sriovConfig.extendedResourceName` — do **not** add the extended resource to `resources`
yourself, or it is listed twice. Set only `cpu` and `memory` under `resources`.

For exclusive CPU pinning the DPDK container needs **Guaranteed** QoS, which requires more
than the kubelet static policy: every container in the pod must have **equal CPU and memory
requests and limits**, and CPU must be a whole number. The application container's example
below is balanced, but if you enable the IPsec or O1 sidecars — whose `resources` default to
`{}` — you must give each of them equal requests and limits too, or the pod drops to
Burstable and the DPDK entrypoint rejects the shared cgroup CPU set even with the static
policy on. See [Operations](operations.md#resources-and-qos).

```yaml
# chart: ocudu-gnb
# The pool named here must advertise vfio-pci-bound VFs (see Per-chart resource name).
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

The name in `sriovConfig.extendedResourceName` must match the pool the device plugin
advertises; the chart then requests that resource for you. A DPDK datapath also needs
hugepages; see [Hugepages](hugepages.md).

### The application config must carry `hal.eal_args`

Requesting a VF through `sriovConfig` is only half of it. The chart injects the VF into the
pod, but the DPDK datapath is driven by the **application config** (the OCUDU gNB/DU YAML you
supply), and the entrypoint **refuses to start** when a VF is present but the config has no
`hal.eal_args`:

- the gNB entrypoint fatal-errors with `SR-IOV devices detected but no 'hal' section found in
  config` (and a second check for `eal_args`);
- the DU entrypoint additionally requires a **runtime-rewritable `@(...)` CPU mapping** inside
  `eal_args`, failing with `hal.eal_args must contain a runtime-rewritable @(...) CPU mapping`
  — the entrypoint rewrites the CPU list inside `@(...)` to match the pod's assigned cores.

The default gNB config ships a `ru_ofh` section but no `hal`, so a VF added via `sriovConfig`
without also supplying `hal.eal_args` crashes on startup. Add a `hal` section to your
application config, for example:

```yaml
# application config (OCUDU gNB/DU YAML), not Helm values
hal:
  eal_args: "--lcores (0-1)@(0-1) -a 0000:3b:02.0"
```

The `@(...)` list is a placeholder — the entrypoint substitutes the pod's actual CPU set at
runtime — but the `@(...)` form **must be present** or the DU entrypoint rejects it. Point
`-a` at the VF BDF (or let the entrypoint substitute it from the device plugin). An SDR/UHD
DU does not use DPDK and needs no `hal` section; set `sriovConfig.enabled: false` instead.

## Verifying

```bash
# The pod got the VF resource it asked for
kubectl describe pod <pod-name> -n <namespace> | grep -A3 "Limits\|Requests"

# The node still has VFs to give out
kubectl describe node <node-name> | grep intel.com/intel_sriov
```

## Troubleshooting

**VFs do not appear**

```bash
ip link show
lspci | grep -i "Virtual Function"
lspci -k -s <VF_BDF>      # check the bound driver
```

**Device plugin not advertising the resource**

```bash
kubectl logs -n kube-system -l app=sriovdp --tail=50
kubectl get configmap -n kube-system sriovdp-config -o yaml
```

**Pod stuck Pending ("Insufficient intel.com/intel_sriov…")**

The node has no free VF, or the name in `resources`/`sriovConfig` does not match the
advertised pool.

```bash
kubectl describe node <node-name> | grep intel.com/intel_sriov
kubectl describe pod <pod-name> -n <namespace>
```

## See also

- [Network modes](network-modes.md) — CNI vs host network, and how the chart requests a VF.
- [Hugepages](hugepages.md) — hugepages for the DPDK datapath.
- [Operations](operations.md) — CPU pinning and Guaranteed QoS for DPDK pods.
