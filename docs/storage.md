# Storage

**Applies to:** `ocudu-gnb`, `ocudu-cu`, `ocudu-du`, `ocudu-cu-cp`, `ocudu-cu-up`.

Each RAN chart writes its debugging logs to a volume under `persistence.mountPath`
(`/var/log/ocudu` by default). This guide covers the three volume shapes — `emptyDir`,
PVC and `hostPath` — the log files themselves, and the `hostPath` ownership pitfall. The
only thing stored here is logs; none of these charts keeps application state on disk.

## Jump to

| If you want to… | Go to |
|---|---|
| see what each chart defaults to | [Defaults per chart](#defaults-per-chart) |
| understand the three volume types | [Volume types](#volume-types) |
| keep logs across pod restarts | [Enabling persistence](#enabling-persistence) |
| keep each run's logs in a separate timestamped directory | [Log files and `preserveOldLogs`](#log-files-and-preserveoldlogs) |
| fix a permission-denied on `hostPath` | [hostPath ownership](#hostpath-ownership) |

## Defaults per chart

`persistence.enabled` controls whether a persistent volume is used. When it is `false`, logs
go to an `emptyDir`, which keeps the pod reschedulable onto any node but loses the logs when
the pod is removed. `persistence.type` selects PVC or `hostPath` when persistence is on.

| Chart | `persistence.enabled` | `persistence.type` | `preserveOldLogs` |
|-------|:---------------------:|:------------------:|:-----------------:|
| `ocudu-gnb` | `false` | `pvc` | `true` |
| `ocudu-cu` | `false` | `pvc` | `false` |
| `ocudu-du` | `false` | `pvc` | `true` |
| `ocudu-cu-cp` | `false` | `pvc` | `false` |
| `ocudu-cu-up` | `false` | `pvc` | `false` |

All five charts default to persistence **off**, so logs go to an `emptyDir` and the pod
stays drainable. `persistence.type` (`pvc` by default) only selects the volume shape once
persistence is turned on. `preserveOldLogs` defaults vary (`true` on `ocudu-gnb` and
`ocudu-du`, `false` elsewhere) — see [Log files and `preserveOldLogs`](#log-files-and-preserveoldlogs)
for what it does. Always check your chart's `values.yaml` for its own defaults rather than
assuming another chart's.

## Volume types

| Type | When persistence is | Survives pod restart | Pins pod to a node | Best for |
|------|---------------------|:--------------------:|:------------------:|----------|
| `emptyDir` | `enabled: false` | ❌ | ❌ | the default; drainable, logs are ephemeral |
| PVC | `enabled: true`, `type: pvc` | ✅ | only with a node-bound StorageClass | cloud and most clusters |
| `hostPath` | `enabled: true`, `type: hostPath` | ✅ | ❌ (not automatically) | bare-metal local debugging |

A direct `hostPath` volume does **not** pin the pod to a node: Kubernetes adds no scheduling
constraint for it, so the pod can be rescheduled onto a different node, where it will mount
or create the same path locally — and the original node's logs are not there. If you need
the pod to stay on the node that holds the logs, add that constraint yourself with a
`nodeSelector` or `nodeAffinity` (see [hostPath ownership](#hostpath-ownership)). A
node-bound StorageClass (for example a local-path provisioner backed by a local
PersistentVolume) is different — a local PV carries node affinity and really does constrain
scheduling. For a pod that has to survive a node drain, prefer an `emptyDir` (persistence
off) or a network-backed StorageClass — see the [Operations](operations.md) guide for the
drain story and the CNTi `hostpath_mounts` / `node_drain` checks.

## Enabling persistence

### PVC (cloud and most clusters)

```yaml
# chart: ocudu-cu
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: ""   # "" uses the cluster's default StorageClass
    accessMode: ReadWriteOnce
    size: 10Gi
  mountPath: "/var/log/ocudu"
```

Leave `storageClassName` empty to use the cluster default, or name a specific class
(`kubectl get storageclass` lists them). `accessMode: ReadWriteOnce` suits a single-replica
pod; use `ReadWriteMany` only with a StorageClass that supports it.

### hostPath (bare-metal local debugging)

```yaml
# chart: ocudu-gnb
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/debugging-logs"
    type: DirectoryOrCreate
  mountPath: "/var/log/ocudu"
```

`hostPath.type` is usually `DirectoryOrCreate` (create the directory if it is absent) or
`Directory` (it must already exist). See [hostPath ownership](#hostpath-ownership) below
before you use it — the directory must be writable by uid 1000.

### Disabling persistence

```yaml
# chart: ocudu-gnb
persistence:
  enabled: false
```

Logs then go to an `emptyDir` and are lost when the pod is removed. If the application's
configured log path points at a subdirectory that only the persistent volume would create —
for example `log.filename: /var/log/ocudu/debugging-logs/<name>.log` — that directory will
not exist under a bare `emptyDir`. Either enable persistence or point the log file directly
at `mountPath` (`/var/log/ocudu/<name>.log`).

## Log files and `preserveOldLogs`

`persistence.preserveOldLogs` controls what the entrypoint does with the previous run's logs
when the container restarts:

- **`true`** — the entrypoint creates a fresh timestamped directory under `mountPath`,
  rewrites the application's configured log paths to point into it, and updates a `current`
  symlink to the newest one. Earlier runs are kept in their own timestamped directories
  rather than overwritten. (It does **not** append to a single file.)
- **`false`** — logs are written to the fixed path and the previous run's file is overwritten
  on each start.

What this preserves depends on the volume, and on the distinction between a **container
restart** and a **pod replacement**:

- An `emptyDir` survives a container restart but not a pod replacement — it is recreated
  empty when the pod is rescheduled or recreated. So with `preserveOldLogs: true` on an
  `emptyDir`, timestamped directories from earlier *container* restarts persist for the life
  of the pod, but all of them are lost when the pod is replaced.
- A PVC or `hostPath` volume survives pod replacement, so the timestamped history persists
  across it.

`preserveOldLogs` is wired slightly differently per chart: `ocudu-cu`, `ocudu-du`,
`ocudu-cu-cp` and `ocudu-cu-up` pass `PRESERVE_OLD_LOGS` to the entrypoint whether or not
persistence is enabled (so it takes effect on an `emptyDir` too), while `ocudu-gnb` passes it
only when `persistence.enabled: true`. Defaults differ per chart (see
[Defaults per chart](#defaults-per-chart)).

With [O1](o1.md) enabled, the `o1-adapter` and `netconf-server` sidecars can also tee their
output to files on the same volume (`o1.o1Adapter.fileLog` / `o1.netconfServer.fileLog`).
Those files are appended to, are not rotated, and only survive pod replacement when
`persistence.enabled` is true. See the O1 guide for that part.

## hostPath ownership

Every RAN pod runs as uid 1000 (`podSecurityContext.fsGroup: 1000`). `fsGroup` sets group
ownership for PVC and `emptyDir` volumes, but **Kubernetes does not apply it to `hostPath`
volumes**. A directory created by `DirectoryOrCreate`, or one created by root, is therefore
owned by root and the uid-1000 process cannot write it — the pod logs a permission error.

Pre-create the directory on the node with the right ownership before deploying. Adjust the
path to match `persistence.hostPath.path` in your values:

```bash
# on the node, as root
mkdir -p /mnt/debugging-logs
chown 1000:1000 /mnt/debugging-logs
chmod 755 /mnt/debugging-logs
```

To check an existing one:

```bash
ls -ld /mnt/debugging-logs   # expect owner/group 1000
```

Because a `hostPath` directory lives on one specific node, the logs are only there if the
pod runs on that node — but a direct `hostPath` does not make that happen on its own.
Kubernetes will schedule the pod onto any eligible node unless you constrain it, so pin it
with a `nodeSelector` or `nodeAffinity` to the node that holds the directory. That manual
pinning is also what makes `hostPath` incompatible with a clean node drain; see the
[Operations](operations.md) guide.

## See also

- Your chart's README for the Storage feature row, its `persistence` defaults, and the
  application log path it ships.
- [Operations](operations.md) — why persistence off keeps the pod drainable, and the CNTi
  `hostpath_mounts` / `node_drain` checks.
- [Security](security.md) — the pod security context and `fsGroup`.
- [O1](o1.md) — persistent sidecar logs on the same volume.
- [Kubernetes storage concepts](https://kubernetes.io/docs/concepts/storage/) and
  [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/).
