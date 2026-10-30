# Operations

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Running a RAN chart day to day: sizing it, upgrading it without overlapping pods, letting
it report ready at the right moment, and keeping a node drain from being blocked. Every
RAN pod is a single-replica, stateful workload, which is what shapes the defaults below.

## Jump to

| If you want to… | Go to |
|---|---|
| set resources and get Guaranteed QoS | [Resources and QoS](#resources-and-qos) |
| upgrade without old and new pods overlapping | [Upgrades and the Recreate strategy](#upgrades-and-the-recreate-strategy) |
| understand when the pod reports ready | [Startup, liveness and readiness probes](#startup-liveness-and-readiness-probes) |
| keep a PodDisruptionBudget from blocking maintenance | [PodDisruptionBudget](#poddisruptionbudget) |
| make `kubectl drain` work | [Surviving a node drain](#surviving-a-node-drain) |
| change the container's init process | [Init process (`initCommand`)](#init-process-initcommand) |

## Resources and QoS

`resources.requests` and `resources.limits` must each set `cpu` and `memory`. The chart
does not render without them — this is deliberate, so a pod is never scheduled without a
size. Setting the application's requests equal to its limits is necessary for the
**Guaranteed** QoS class, but **not sufficient on its own**: Kubernetes grants Guaranteed
only when *every container in the pod* has equal CPU and memory requests and limits. The
`ipsec` sidecar and the O1 `o1-adapter` / `netconf-server` sidecars all default to empty
`resources: {}`, so enabling any of them drops the pod to **Burstable** even when the
application container is balanced. If you need Guaranteed with a sidecar on, give that
sidecar matching requests and limits too (`ipsec.resources`, `o1.o1Adapter.resources`,
`o1.netconfServer.resources`). Guaranteed is what a real-time RAN workload needs: it is the
last to be evicted under node pressure and its CPU reservation is honoured.

The default request and limit per chart:

| Chart | Default `cpu` | Default `memory` |
|-------|:-------------:|:----------------:|
| `ocudu-gnb` | `4` | `4Gi` |
| `ocudu-cu` | `2` | `4Gi` |
| `ocudu-du` | `4` | `4Gi` |
| `ocudu-cu-cp` | `1` | `4Gi` |
| `ocudu-cu-up` | `2` | `4Gi` |

The `4Gi` default leaves room for the 2 GiB buffer pool OCUDU allocates at startup. Size up
from there for production — the gNB README shows a 12 CPU / 16Gi example.

```yaml
# chart: ocudu-cu
resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 2
    memory: 4Gi
```

On the DPDK charts (`ocudu-gnb`, `ocudu-du`) `resources` also carries the hugepages request
that backs DPDK; see the [guides index](README.md) for the Hugepages guide (added with the
node-setup guides) for that part.

## Upgrades and the Recreate strategy

Every RAN chart sets `deploymentStrategy.type: Recreate`. The old pod is fully terminated
before the new one starts, so the old and new processes never run at the same time. These
are single-replica, stateful workloads that bind fixed addresses and (with persistence)
a node-local log volume; a rolling update that briefly ran two pods would double-bind those
addresses and race on the volume.

Upgrade by re-running `helm upgrade` with the same values file you installed with. Do not
hard-code a chart version in the command — pin it in your own tooling if you must, but the
guides and READMEs leave it out so the examples do not go stale:

```bash
helm upgrade <release> <chart> -f my-values.yaml
```

Because the strategy is `Recreate`, an upgrade is a short outage: the pod goes away and
comes back. Plan for it the same way you would plan a restart.

Switch to `RollingUpdate` only if you have validated that your runtime, config and storage
tolerate two overlapping pods — for most deployments they do not.

## Startup, liveness and readiness probes

All five charts run a liveness probe and a readiness probe on the application container,
both `exec` probes that run `pgrep <binary>`, and all five also run a **startup probe** in
front of those two. All three probes have an `enabled` flag, and leaving them on is
recommended.

| Chart | Startup probe | Startup budget | Readiness `initialDelaySeconds` / `timeoutSeconds` / `failureThreshold` |
|-------|:-------------:|:--------------:|-------------------------------------------------------------------------|
| `ocudu-gnb` | ✅ | `periodSeconds: 2` × `failureThreshold: 90` = 180s | `0` / `3` / `6` |
| `ocudu-cu` | ✅ | 180s | `0` / `3` / `6` |
| `ocudu-du` | ✅ | 180s | `0` / `3` / `6` |
| `ocudu-cu-cp` | ✅ | 180s | `0` / `3` / `6` |
| `ocudu-cu-up` | ✅ | 180s | `0` / `3` / `6` |

The startup probe holds off liveness and readiness until the application binary is running,
so neither needs padding on `initialDelaySeconds` (readiness starts at `0`) and the pod
reports Ready within one probe period of the process appearing. The readiness
`timeoutSeconds` (`3`) is deliberately above the Kubernetes default of `1`: readiness is an
`exec` probe, and under node pressure spawning `pgrep` can exceed a 1s timeout, and with a
single replica a flapping readiness is a real interface outage, not a cosmetic blip. The
`livenessProbe` defaults (`initialDelaySeconds: 90`, `periodSeconds: 30`, `failureThreshold:
3`) are the same across all five.

The 180s startup budget also covers O1 mode, where the entrypoint waits (up to
`CONFIG_CREATE_TIMEOUT`, 120s) for the adapter to generate the config before the application
starts. In O1 mode on every chart the liveness probe switches from `pgrep` to an `httpGet`
on the adapter's `/config-healthy` endpoint — see the [O1](o1.md) guide.

## PodDisruptionBudget

Every chart ships a PodDisruptionBudget, enabled by default:

```yaml
# chart: ocudu-cu
podDisruptionBudget:
  enabled: true
  minAvailable: 0
  unhealthyPodEvictionPolicy: AlwaysAllow
```

The defaults are tuned for a single-replica workload:

- **`minAvailable: 0`** permits the pod to be evicted during a voluntary disruption (a node
  drain or cluster upgrade). With one replica, any value above 0 would block the drain
  outright, since there is no second pod to keep available. Use `maxUnavailable: 1` instead
  of `minAvailable` only if you run more than one replica — set one or the other, never both.
- **`unhealthyPodEvictionPolicy: AlwaysAllow`** lets an unhealthy pod be evicted, so a stuck
  pod cannot block node maintenance and a replacement can be scheduled. `IfHealthyBudget`
  protects unhealthy pods and can wedge a drain; it is not recommended.

> `minAvailable: 0` permits the eviction but does not by itself bring the pod back —
> rescheduling does, which is what the [node drain](#surviving-a-node-drain) section is
> about.

## Surviving a node drain

Nothing in the chart defaults pins the pod to a node. Keep it that way if `kubectl drain`
has to work and the pod has to come back on another node:

- leave `persistence.enabled: false`, or use a StorageClass that is not node-bound. A
  node-bound volume pins the pod: a local PersistentVolume (for example behind a local-path
  provisioner) carries node affinity and constrains scheduling. A direct `hostPath` does not
  pin the pod by itself, but it only has the logs on the one node, so you typically add a
  `nodeSelector` / `nodeAffinity` to keep the pod there — which then blocks a clean drain
  just the same (see the [Storage](storage.md) guide);
- select nodes by a capability label rather than `kubernetes.io/hostname`, so the pod can
  land on any node that qualifies;
- keep `podDisruptionBudget.minAvailable: 0` (the default) so the eviction is permitted.

**The drain command needs `--delete-emptydir-data`.** Every RAN pod uses at least one
`emptyDir` (logs go to one whenever persistence is off, and other `emptyDir` volumes are
always present), and `kubectl drain` refuses to evict a pod backed by an `emptyDir` unless
you explicitly accept that its contents are lost. The PodDisruptionBudget and scheduling
settings above are not enough on their own:

```bash
kubectl drain <node> --delete-emptydir-data --ignore-daemonsets
```

The CNTi `node_drain` and `hostpath_mounts` checks exercise exactly this: a pod that
mounts a `hostPath` or is pinned by node name fails them. See the [Security](security.md)
guide for how the CNTi checks map onto the chart.

## Init process (`initCommand`)

Every RAN container runs an init process as PID 1 that reaps zombie processes and forwards
signals to the application — satisfying the CNTi zombie-handling checks. The default on all
five charts is catatonit with `-g`:

```yaml
# chart: ocudu-cu
initCommand:
  - /usr/bin/catatonit
  - -g
  - --
```

`-g` runs catatonit as a process-group signal forwarder, so a signal reaches the whole
group, not just PID 2. Override `initCommand` only when the image provides a different init
binary — for example tini, run as a child subreaper and process-group signal forwarder with
`-s -g`:

```yaml
# chart: ocudu-gnb
initCommand:
  - /usr/bin/tini
  - -s
  - -g
  - --
```

Which init binaries are packaged depends on the image's base OS. catatonit is widely
available; tini is not packaged on every distribution:

| OS | catatonit | tini |
|----|-----------|------|
| Ubuntu 24.04 | Yes (`universe`) | Yes (`universe`) |
| Ubuntu 26.04 | Yes (`universe`) | Yes (`universe`) |
| CentOS Stream 10 | Yes (`AppStream`) | No |
| UBI 10 | Yes (`AppStream`) | No |
| Hummingbird | Yes | No |
| Arch Linux (2026.08.01) | Yes (`extra`) | AUR only |

If you point `initCommand` at a binary the image does not carry, the container fails to
start.

## See also

- Your chart's README for the Operations feature rows and chart-specific facts (the log
  line that shows it started, the exact resource example).
- [Storage](storage.md) — persistence, log files, and why `hostPath` needs manual node
  pinning.
- [Security](security.md) — Pod Security Standards, capabilities, and the CNTi checks that
  interact with persistence (`node_drain`, `hostpath_mounts`).
- [O1](o1.md) — how O1 mode changes pod startup and what the startup budget covers.
