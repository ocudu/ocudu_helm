# Security context and capabilities

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Every RAN chart runs its **application container** non-root (uid 1000), drops all Linux
capabilities and adds back only the few the application needs, mounts no service-account
token and binds no Role. The two settings that are deliberately **not** at their most
restrictive value — `securityContext.allowPrivilegeEscalation: true` and a short
`capabilities.add` list — are what let the image's file capabilities take effect. This guide
explains why, what each capability buys, which charts add which, and what that means for Pod
Security Standards and the CNTi Test Suite.

Two optional sidecars have a different posture and are called out below: the **IPsec**
sidecar runs as **root** by design (see
[The IPsec sidecar runs as root](#the-ipsec-sidecar-runs-as-root)), and the **O1** sidecars
ship an empty `securityContext` (see [Pod security context](#pod-security-context)).

## Jump to

| If you want to… | Go to |
|---|---|
| see which capabilities your chart adds and why | [Capabilities per chart](#capabilities-per-chart) |
| understand why `allowPrivilegeEscalation` is `true` | [File capabilities and `allowPrivilegeEscalation`](#file-capabilities-and-allowprivilegeescalation) |
| know why the IPsec sidecar runs as root | [The IPsec sidecar runs as root](#the-ipsec-sidecar-runs-as-root) |
| pick a Pod Security Standards level for the namespace | [Pod Security Standards](#pod-security-standards) |
| label the namespace | [Namespace labels](#namespace-labels) |
| know why the pod has no API token | [Service account](#service-account) |
| read the pod security context defaults | [Pod security context](#pod-security-context) |
| understand the CNTi check results | [CNTi notes](#cnti-notes) |
| cover the DPDK privileged fallback | [Host-network fallback (DPDK charts)](#host-network-fallback-dpdk-charts) |

## Capabilities per chart

Each chart's default `securityContext.capabilities.add` carries only what its application
binary needs. The image bakes these into the binary as **permitted-only file capabilities**
(`setcap ...+p`), and the application raises them at startup, so a capability left out of
`capabilities.add` only disables what depends on it — it does not stop the pod.

| Chart | Binary | Default `capabilities.add` | Why |
|-------|--------|----------------------------|-----|
| `ocudu-gnb` | `gnb` | `SYS_NICE`, `IPC_LOCK` | real-time threads, DPDK DMA pinning |
| `ocudu-du` | `odu` | `SYS_NICE`, `IPC_LOCK` | real-time threads, DPDK DMA pinning |
| `ocudu-cu` | `ocu` | `SYS_NICE` | real-time threads |
| `ocudu-cu-cp` | `ocucp` | `SYS_NICE` | real-time threads |
| `ocudu-cu-up` | `ocuup` | `SYS_NICE` | real-time threads |

All five also set `allowPrivilegeEscalation: true`, `privileged: false` and `drop: ["ALL"]`.

What each capability does:

- **`SYS_NICE`** — the application runs its worker pool, I/O thread and (on the DPDK charts)
  fronthaul timing and I/O threads at `SCHED_FIFO` real-time priority. Without it the binary
  still starts, prints `Scheduling priority of thread "..." not changed`, and runs those
  threads at normal priority. On `ocudu-gnb` and `ocudu-du` that means missed fronthaul
  deadlines (`Real-time timing worker woke up late`, `dropped late downlink resource grid`).
- **`IPC_LOCK`** — only on the DPDK charts (`ocudu-gnb`, `ocudu-du`). DPDK maps its hugepage
  memory for DMA through VFIO, and the kernel counts that pinned memory (at least one 1 GiB
  hugepage) against the container's `RLIMIT_MEMLOCK` unless the process holds `IPC_LOCK`.
  Kubernetes cannot set that limit — a container inherits it from the runtime, and a runtime
  started by systemd inherits systemd's 8 MiB default unless its unit raises it. Without the
  capability DPDK stops with `EAL: Cannot set up DMA remapping, error 12 (Cannot allocate
  memory)` and the kernel logs `vfio_pin_pages_remote: RLIMIT_MEMLOCK (8388608) exceeded`.
  Only a node whose runtime has an unlimited locked-memory limit works without it. The
  CU-side charts run no DPDK datapath, so they do not add it.
- **`PERFMON`** — reads the CPU energy counters (RAPL) with `perf_event_open()` for the power
  metric (`metrics.layers.enable_app_usage`). No chart adds it, in `values.yaml` or
  `values-o1.yaml`, and their configs turn `enable_app_usage` off. Turn both on when you
  collect metrics, for example with the `grafana-ocudu` chart, and want the power reading;
  without it the power reads 0 W. `capabilities.add` is a list, so repeat the chart's defaults:

  ```yaml
  # chart: ocudu-gnb or ocudu-du
  securityContext:
    capabilities:
      add: [SYS_NICE, IPC_LOCK, PERFMON]
  # chart: ocudu-cu, ocudu-cu-cp or ocudu-cu-up
  securityContext:
    capabilities:
      add: [SYS_NICE, PERFMON]
  ```

See the [guides index](README.md) for Hugepages and SR-IOV setup (the DPDK charts'
node-side requirements), and your chart's `values.yaml` for the exact `securityContext`
block.

## File capabilities and `allowPrivilegeEscalation`

The images carry the capabilities above as **permitted-only** file capabilities (no effective
bit). Two kernel rules follow from that:

- On `execve()` the process gets whichever of the file's permitted capabilities the container
  grants in `capabilities.add`, and the application raises them itself at startup. Removing one
  from `capabilities.add` therefore only disables what depends on it, as above — it never
  blocks the pod.
- `allowPrivilegeEscalation: false` sets `no_new_privs`, under which the kernel **ignores file
  capabilities entirely**. The process would then start with none of them. This is why the
  charts ship `allowPrivilegeEscalation: true`: it is what makes the file capabilities take
  effect. This is a real security trade-off, not a no-op — the field controls whether a
  process can gain **more** privileges than its parent, including via setuid binaries or other
  file capabilities, so enabling it widens what a compromised process could do. The mitigation
  is the restricted container context around it: the process starts non-root, `privileged`
  stays `false`, and the capability set is reduced to the entries in `capabilities.add`
  (listed above). Because privilege escalation remains enabled, image hardening and avoiding
  unnecessary setuid/file-capability binaries are still important.

> **Older images.** An image that sets the *effective* bit (`getcap /usr/local/bin/<binary>`
> shows `=ep`) refuses to start (`EPERM`) unless the container grants every capability the
> binary declares. Older OCUDU `ocucp` and `ocuup` images also carried `IPC_LOCK` with the
> effective bit set; with one of those, add `IPC_LOCK` back to `capabilities.add` on
> `ocudu-cu-cp` or `ocudu-cu-up`. Current images use permitted-only capabilities, so the
> chart defaults are the minimum each needs.

The DPDK charts have one more image requirement tied to `setcap`: `setcap` triggers ld.so
secure-execution mode, which strips `LD_LIBRARY_PATH`, so the image must make the DPDK/UHD/ROHC
libraries findable through `/etc/ld.so.conf.d` + `ldconfig` instead. The OCUDU images are built
this way; a custom image needs the same.

## The IPsec sidecar runs as root

The non-root/`drop: ["ALL"]` posture above describes the **application container**. When
[IPsec](ipsec.md) is enabled, the pod also gains an IPsec sidecar, and on **all five charts**
that sidecar runs as **root** by design:

```yaml
# chart: ocudu-cu — ipsec.securityContext default
runAsUser: 0
runAsNonRoot: false
privileged: false
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
  add:
    - NET_ADMIN         # configure XFRM state/policy and the tunnel interface
    - NET_BIND_SERVICE  # bind IKE on the privileged port 500 (dropped if ikeOnNatTPortOnly)
seccompProfile:
  type: RuntimeDefault
```

This is a deliberate trade-off, not an oversight. The sidecar needs `NET_ADMIN` to set up
the XFRM state/policy and the tunnel interface, and `NET_BIND_SERVICE` to bind IKE on the
privileged UDP port 500 — the chart drops `NET_BIND_SERVICE` automatically when
`ipsec.ikeOnNatTPortOnly: true` (IKE on 4500 only, no privileged port), leaving just
`NET_ADMIN`. Running the sidecar as uid 0 with `allowPrivilegeEscalation: false` is stronger
than the non-root alternative, which would need those capabilities as **file** capabilities
on the binary *plus* `allowPrivilegeEscalation: true` to let them take effect — widening what
a compromised process could gain. So the sidecar stays root but keeps `privileged: false`,
`allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `drop: ["ALL"]` and the
default seccomp profile, and adds only the one or two capabilities it needs.

The practical consequence: with IPsec on, the pod is no longer all-non-root, and a namespace
can no longer be described as running only uid-1000 containers. This is covered by the same
**Privileged** Pod Security level the application container already requires. The sidecar's
`NET_ADMIN` capability is outside Baseline's allow-list, while its uid 0 is additionally
outside Restricted (Baseline itself permits uid 0). See [IPsec](ipsec.md) for when and how the
sidecar is added.

## Pod Security Standards

The [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
define three levels. Every chart needs the namespace to enforce **Privileged**:

| Level | Works | Why |
|-------|:-----:|-----|
| Privileged | ✅ | imposes no restriction on the capabilities and settings these charts use |
| Baseline | ❌ | Baseline's allowed-capability list does not include `SYS_NICE`, `IPC_LOCK` or `PERFMON` |
| Restricted | ❌ | Restricted allows no added capability except `NET_BIND_SERVICE` and requires `allowPrivilegeEscalation: false` |

This holds for the CU-side charts too: even without DPDK, `SYS_NICE` (and `PERFMON` where
added) is outside Baseline's list, and `allowPrivilegeEscalation: true` is outside Restricted.
Deploy in a dedicated namespace so the Privileged level applies to nothing else.

## Namespace labels

Of the three Pod Security Admission modes, only `enforce` actually blocks a non-conforming
pod; `audit` and `warn` just annotate the audit log and print warnings. The example below sets
all three to the Privileged level, which is what these charts need to run:

```bash
kubectl create namespace <namespace>
kubectl label namespace <namespace> \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
```

`enforce=privileged` is the setting that lets the pods start. Setting `audit` and `warn` to
`privileged` as well means neither produces any warnings or audit annotations — which is fine
if you only want the charts to run. If instead you want visibility into how far the pods sit
from a tighter level, leave `audit`/`warn` at a stricter level such as `baseline` or
`restricted`: they will then annotate and warn about the capabilities and
`allowPrivilegeEscalation` these charts use, without blocking the pods (only `enforce` blocks).

## Service account

Nothing in any RAN pod — not the entrypoint, not the application binary — uses the Kubernetes
API. Every chart therefore creates a ServiceAccount of its own for the pod, named after the
release, and:

- **mounts no token** (`automountServiceAccountToken: false` on both the ServiceAccount and the
  pod spec), so a compromised container holds no API credential by default;
- **binds no Role or RoleBinding**, so the chart grants the account no workload-resource
  permissions. This is not the same as the account being able to do nothing in the API: an
  authenticated ServiceAccount normally still has the cluster's default API-discovery access,
  and any existing cluster-wide or group-scoped binding (for example one targeting all
  authenticated users or the namespace's service accounts) would apply to it too. What the
  chart guarantees is that it adds no permissions and mounts no token.

A dedicated account, rather than the namespace's `default`, keeps the pod apart from every
other workload: a Role bound to `default` by another chart never applies to it, the audit log
attributes API calls to this release's ServiceAccount identity (shared by all of its replicas
and containers, not to a single pod), and identity-keyed policies (RBAC, service-mesh
authorization, cloud IAM) can target it. This satisfies CIS Kubernetes Benchmark 5.1.5 and
5.1.6, and the CNTi `service_account_mapping` and `dedicated_service_account` checks.

`serviceAccount.annotations` adds annotations to the account — for example a cloud identity
binding:

```yaml
# chart: ocudu-cu
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ocudu-cu
```

A sidecar that needs the Kubernetes API is a change to the chart, not a value: it would need a
token mounted on that container and a Role for what it reads. If a sidecar reports `Forbidden`
or finds no token under `/var/run/secrets/kubernetes.io/serviceaccount`, that is this design,
not a misconfiguration.

## Pod security context

Every chart runs the pod non-root with a fixed uid/gid:

```yaml
# chart: ocudu-cu
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile:
    type: RuntimeDefault
```

`fsGroup: 1000` lets the non-root process write the volume types Kubernetes manages group
ownership for — PVCs and `emptyDir`. It does **not** change ownership of every mounted volume:
in particular it does not apply to `hostPath`, whose directories must already have ownership
and permissions that allow uid/gid 1000 to write. See the [guides index](README.md) for
Storage and how `fsGroup` interacts with `hostPath` ownership.

`seccompProfile: {type: RuntimeDefault}` applies the container runtime's default seccomp
filter to every container in the pod. It is one of the requirements the Restricted Pod
Security level checks — the application container already satisfies it; what keeps these
charts off Restricted is the added capabilities and `allowPrivilegeEscalation: true`, not
seccomp.

With [O1](o1.md) the `o1-adapter` and `netconf-server` sidecars also run as uid 1000, and
`values-o1.yaml` adds the pod sysctl `net.ipv4.ip_unprivileged_port_start: "0"` under
`podSecurityContext` so the non-root netconf-server can bind `o1.o1Port` (830). It is a safe
sysctl on the kubelet's default allow-list, so no `allowedUnsafeSysctls` change is needed.
Kubernetes rejects `net.*` sysctls when `network.hostNetwork: true`, so **O1 and host
networking are incompatible under the default O1 values**: the two together are rejected at
apply time because of that sysctl. It is not an absolute limit, though — if the node's
`net.ipv4.ip_unprivileged_port_start` already permits binding 830, you can drop the pod sysctl
and run the combination:

```yaml
# chart: ocudu-gnb
# with: values-o1.yaml
network:
  hostNetwork: true
podSecurityContext:
  sysctls: []   # remove the pod-level net.* sysctl so hostNetwork is accepted
```

This relies on node-level configuration instead; see
[Network modes](network-modes.md) for the node-side alternative.

The O1 sidecars (`o1.o1Adapter`, `o1.netconfServer`) ship an **empty** `securityContext: {}`,
which the chart renders verbatim. They are therefore **not hardened** at the container level:
they inherit only the pod-level settings (uid/gid 1000 and the `RuntimeDefault` seccomp
profile) and otherwise take Kubernetes defaults — notably **no `drop: ["ALL"]`** and the
default `allowPrivilegeEscalation` (which is permissive for a non-root container). This is
weaker than the application container, which explicitly drops all capabilities. If you need
them hardened, set `o1.o1Adapter.securityContext` / `o1.netconfServer.securityContext`
yourself (for example `allowPrivilegeEscalation: false`, `capabilities: {drop: ["ALL"]}`,
`readOnlyRootFilesystem: true`). Giving them a restricted default in the charts is a possible
follow-up. See [O1](o1.md).

## CNTi notes

The chart pipelines run the essential tests of the
[CNTi Test Suite](https://github.com/cnti-testcatalog/testsuite) against each chart. Two checks
interact with the capabilities above:

- **`insecure_capabilities`** fails while `PERFMON` is granted — it is on kubescape's
  insecure-capability list (C-0046). This is why no chart adds it by default.
- **`privilege_escalation`** fails regardless, because the file capabilities need
  `allowPrivilegeEscalation: true` (see
  [File capabilities and `allowPrivilegeEscalation`](#file-capabilities-and-allowprivilegeescalation)).
  Setting it `false` would pass the check but leave the application with none of its
  capabilities.

The service-account checks (`service_account_mapping`, `dedicated_service_account`, kubescape
C-0034) pass out of the box, as described under [Service account](#service-account). The
`hostpath_mounts` and `node_drain` checks interact with persistence, not security context —
see the [guides index](README.md) for Storage and Operations.

## Host-network fallback (DPDK charts)

`ocudu-gnb` and `ocudu-du` also support a host-network fallback for nodes without the SR-IOV
Device Plugin. It needs a privileged container and `NET_ADMIN`:

```yaml
# chart: ocudu-gnb
network:
  hostNetwork: true
securityContext:
  privileged: true
  capabilities:
    add:
      - SYS_NICE
      - NET_ADMIN
```

This is far less isolated than the default. `privileged: true` gives the container **all**
Linux capabilities and runs it without the configured seccomp profile, so the explicit
`capabilities.add` list above grants nothing extra — it is redundant under `privileged` and
kept only to document intent. The container is effectively unconfined, not limited to
`SYS_NICE` and `NET_ADMIN`.

Host networking also changes NetworkPolicy. **This chart does not render its NetworkPolicy
when `network.hostNetwork` is true** (the template is gated on `not .Values.network.hostNetwork`),
so the chart applies no policy to the pod at all; more generally, Kubernetes itself treats
NetworkPolicy for host-network pods as implementation-dependent. Either way, do not rely on a
NetworkPolicy here.

Because of all this it only works under the Privileged Pod Security level and should be a last
resort. See the [guides index](README.md) for Network modes (when it is needed) and
SR-IOV setup (the preferred path). The CU-side charts (`ocudu-cu`, `ocudu-cu-cp`,
`ocudu-cu-up`) carry no user-plane fronthaul datapath and so do not offer this *privileged*
mode — but they do still support plain `network.hostNetwork: true` without a privileged
container (they have no SR-IOV datapath to fall back from); see
[Network modes](network-modes.md).

## See also

- Your chart's README for the Security feature row and chart-specific facts.
- [O1](o1.md) — the sidecars' security context and the O1 sysctl.
- The [guides index](README.md) for Operations (resources and QoS, probes,
  PodDisruptionBudget, node drain), Network modes and SR-IOV setup (the DPDK charts'
  networking and node-side requirements).
