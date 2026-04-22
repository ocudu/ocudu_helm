# Security Configuration Guide

This guide covers security aspects of deploying the OCUDU CU/DU Helm chart, including Pod Security Standards, RBAC, security contexts, and Pod Disruption Budgets.

## Table of Contents

- [Pod Security Standards](#pod-security-standards)
- [RBAC (Role-Based Access Control)](#rbac-role-based-access-control)
- [Security Contexts](#security-contexts)
- [Pod Disruption Budget](#pod-disruption-budget)
- [Namespace Security](#namespace-security)
- [Production Best Practices](#production-best-practices)

---

## Pod Security Standards

Kubernetes Pod Security Standards (PSS) define security policies at three levels: Privileged, Baseline, and Restricted.

### Compatibility Matrix

| Security Level | Compatible | Notes |
|---------------|-----------|-------|
| **Privileged** | ✅ Yes | Fully compatible with all deployment modes |
| **Baseline** | ✅ Yes | Compatible with SR-IOV mode (non-privileged) |
| **Restricted** | ❌ No | Requires capabilities not allowed by Restricted PSS |

### Why Not Restricted?

The OCUDU gNB requires two Linux capabilities for real-time DPDK operation:

- `SYS_NICE` — `sched_setscheduler(SCHED_FIFO)` on ru_timing / tx / rx threads
- `IPC_LOCK` — `mlock()` on DPDK hugepages

### Recommended Configuration

**For Production (Baseline PSS):**

Use SR-IOV mode with the minimum-privilege shape (chart default from 3.6.0 onward):

```yaml
network:
  hostNetwork: false

sriovConfig:
  enabled: true

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: true   # required so file caps take effect
  privileged: false
  capabilities:
    drop: ["ALL"]
    add:
      - SYS_NICE
      - IPC_LOCK
```

### Prerequisites for the minimum-privilege default

The chart default only works end-to-end when two infra conditions are met. Without them the gNB pod will start but fail at DPDK init or silently fail to transmit.

1. **Image must have file capabilities baked into the `gnb` binary.** The chart-default pod runs as uid=1000. Linux drops inherited capabilities on `execve()` to a non-root uid unless the binary itself declares them via xattrs. The OCUDU Dockerfile should include:
   ```dockerfile
   RUN setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/gnb
   ```
   Verify in the built image with `getcap /usr/local/bin/gnb` → expect `cap_sys_nice,cap_ipc_lock=ep`.

   The image must also make DPDK/UHD/ROHC libs findable without `LD_LIBRARY_PATH` (setcap triggers ld.so secure mode which strips that env var). Add:
   ```dockerfile
   RUN printf '%s\n' \
         /opt/dpdk/<DPDK_VERSION>/lib/x86_64-linux-gnu \
         /opt/dpdk/<DPDK_VERSION>/lib \
         /opt/uhd/<UHD_VERSION>/lib/x86_64-linux-gnu \
         /opt/uhd/<UHD_VERSION>/lib \
         /opt/rohc/lib \
         > /etc/ld.so.conf.d/ocudu.conf \
       && ldconfig
   ```

The OCUDU images are built with these requirements by default, but if using a custom image or older OCUDU image, these steps are necessary.

2. **Node's containerd must enable `device_ownership_from_security_context`.** Without it, `/dev/vfio/<group>` is bind-mounted into the pod as `root:root 0600`, and uid=1000 can't open it. In `/etc/containerd/config.toml` under `[plugins."io.containerd.cri.v1.runtime"]`:
   ```toml
   device_ownership_from_security_context = true
   ```
   Restart containerd. After this, VFIO device nodes exposed to the pod are chown'd to the pod's `runAsUser` / `runAsGroup`.

---

## RBAC (Role-Based Access Control)

The chart creates minimal RBAC resources following the principle of least privilege.

### Created Resources

1. **ServiceAccount**: Unique identity for the gNB pod
2. **Role**: Namespace-scoped permissions
3. **RoleBinding**: Links the Role to the ServiceAccount

### Default Permissions

| Resource | Verbs | Purpose |
|----------|-------|---------|
| `configmaps` | `get`, `list`, `watch` | Read configuration for potential hot-reload |
| `pods` | `get` | Read own pod information |

### Enabling RBAC

RBAC is enabled by default:

```yaml
rbac:
  create: true
```

### Adding Custom Permissions

Add additional rules via `rbac.extraRules`:

```yaml
rbac:
  create: true
  extraRules:
    - apiGroups: [""]
      resources: ["secrets"]
      verbs: ["get"]
    - apiGroups: ["apps"]
      resources: ["deployments"]
      verbs: ["get", "list"]
```

### Disabling RBAC

To disable RBAC resource creation:

```yaml
rbac:
  create: false
```

**Note**: The ServiceAccount will still be created if `serviceAccount.create: true`.

### Troubleshooting RBAC

Check what the service account can do:

```bash
# Check permissions
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:ocudu:ocudu-gnb \
  -n ocudu

# List RBAC resources
kubectl get role,rolebinding -n ocudu
kubectl describe role ocudu-gnb -n ocudu
```

---

## Security Contexts

The chart supports two security context configurations based on the deployment mode.

### Mode 1: SR-IOV with vfio-pci (Recommended)

**Use when**: `hostNetwork: false` and `sriovConfig.enabled: true`

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

securityContext:
  allowPrivilegeEscalation: true   # required for file caps on execve
  privileged: false
  capabilities:
    drop: ["ALL"]
    add:
      - SYS_NICE      # SCHED_FIFO on ru_timing / tx-rx threads
      - IPC_LOCK      # mlock() on DPDK hugepages
```

**Advantages:**
- ✅ Non-root (uid 1000), drops ALL and adds only the two required caps
- ✅ No privileged mode
- ✅ Compatible with Pod Security Baseline
- ✅ NetworkPolicy support

**Requirements:**
- vfio-pci driver loaded; IOMMU enabled in BIOS
- SR-IOV Device Plugin configured
- **Image has** `setcap cap_sys_nice,cap_ipc_lock+ep /usr/local/bin/gnb`
- **Node's containerd has** `device_ownership_from_security_context = true`

See the "Prerequisites for the minimum-privilege default" section above for details on the last two items. See [network-modes.md](network-modes.md) and [sriov-setup.md](sriov-setup.md) for network/SR-IOV setup.

### Mode 2: Host Network (Fallback)

**Use when**: `hostNetwork: true` and `sriovConfig.enabled: false`

```yaml
securityContext:
  privileged: true
  capabilities:
    add:
      - SYS_NICE
      - NET_ADMIN
```

**Advantages:**
- ✅ Simpler setup (no SR-IOV configuration)
- ✅ Direct hardware access

**Disadvantages:**
- ❌ Requires privileged mode
- ❌ Only compatible with Privileged PSS
- ❌ NetworkPolicy bypassed
- ❌ Reduced security isolation

### Pod-Level Security Context

Optional pod-level security context:

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000
```

**Note**: Pod-level security may conflict with privileged container requirements. Test thoroughly.

---

## Pod Disruption Budget

Pod Disruption Budgets (PDB) ensure application availability during voluntary disruptions like node drains and cluster upgrades.

### Configuration

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 0
  unhealthyPodEvictionPolicy: AlwaysAllow
```

### Key Parameters

#### `minAvailable` vs `maxUnavailable`

Use **only one** of these:

- **`minAvailable: 0`** (Recommended for single replica)
  - Allows all pods to be disrupted
  - Doesn't block node maintenance
  - Appropriate for stateless or single-instance workloads

- **`maxUnavailable: 1`** (For multi-replica)
  - Allows one pod to be unavailable at a time
  - Ensures at least N-1 pods remain available

#### `unhealthyPodEvictionPolicy`

Controls how unhealthy pods are handled during eviction:

- **`AlwaysAllow`** (Default, **Recommended for Production**)
  - Unhealthy pods can be evicted
  - Prevents stuck pods from blocking cluster operations
  - Allows self-healing (new pods can replace failed ones)
  - Required by many cloud-native compliance frameworks

- **`IfHealthyBudget`** (Not recommended)
  - Protects unhealthy pods
  - May block node drains if all pods are unhealthy
  - Can cause cluster maintenance issues

---

## Namespace Security

### Pod Security Standards Labels

Apply PSS labels to your namespace based on the deployment mode:

#### For Privileged Mode (hostNetwork: true)

```bash
kubectl create namespace ocudu
kubectl label namespace ocudu \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
```

#### For Baseline Mode (SR-IOV, hostNetwork: false)

```bash
kubectl create namespace ocudu
kubectl label namespace ocudu \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=baseline \
  pod-security.kubernetes.io/warn=baseline \
  --overwrite
```

### NetworkPolicy Isolation

Enable NetworkPolicies for additional network-level security:

```yaml
networkPolicy:
  enabled: true
```

**Note**: Only effective when `hostNetwork: false`. See [networkpolicy.md](networkpolicy.md) for details.

---

## Security Best Practices

### 1. Always Use RBAC

Never disable RBAC in production:

```yaml
rbac:
  create: true  # Always true for production
```

### 2. Prefer Non-Privileged Mode

Use SR-IOV with vfio-pci whenever possible:

```yaml
network:
  hostNetwork: false
sriovConfig:
  enabled: true
securityContext:
  allowPrivilegeEscalation: false
```

### 3. Enable Pod Disruption Budget

Protect against disruptions:

```yaml
podDisruptionBudget:
  enabled: true
  unhealthyPodEvictionPolicy: AlwaysAllow
```

### 4. Apply NetworkPolicies

Restrict network traffic (when using CNI):

```yaml
networkPolicy:
  enabled: true
```

### 5. Define Resource Limits

Prevent resource exhaustion:

```yaml
resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

### 6. Use Namespace Isolation

Deploy in dedicated namespace with appropriate PSS labels:

```bash
kubectl create namespace ocudu
kubectl label namespace ocudu pod-security.kubernetes.io/enforce=baseline
```

### 7. Regular Security Audits

```bash
# Check security contexts
kubectl get pod -n ocudu -o jsonpath='{.items[*].spec.containers[*].securityContext}'

# Verify RBAC
kubectl auth can-i --list --as=system:serviceaccount:ocudu:ocudu-gnb -n ocudu

# Check NetworkPolicies
kubectl get networkpolicy -n ocudu
```

---

## Troubleshooting

### Pod Fails to Start (Security Context Issues)

**Symptom**: Pod in `CreateContainerError` or `CrashLoopBackOff`

**Check**:
```bash
kubectl describe pod <pod-name> -n ocudu
kubectl logs <pod-name> -n ocudu
```

**Common causes**:
1. Missing capabilities
2. Incorrect privileged setting
3. Pod Security Standards violation

**Solution**: Match security context to deployment mode (see [Security Contexts](#security-contexts)).

### RBAC Permission Denied

**Symptom**: "Forbidden" errors in logs

**Check**:
```bash
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:ocudu:ocudu-gnb -n ocudu
```

**Solution**: Verify RBAC is enabled and service account is created:
```bash
kubectl get sa,role,rolebinding -n ocudu
```

### Node Drain Blocked by PDB

**Symptom**: `kubectl drain` hangs or reports PDB violation

**Check**:
```bash
kubectl get pdb -n ocudu
kubectl describe pdb <pdb-name> -n ocudu
```

**Solution**: 
- Ensure `minAvailable: 0` for single-replica deployments
- Set `unhealthyPodEvictionPolicy: AlwaysAllow`
- Check pod health status

---

## Additional Resources

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Pod Disruption Budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Security Context Configuration](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Network Modes Documentation](network-modes.md)
- [SR-IOV Setup Guide](sriov-setup.md)
- [NetworkPolicy Configuration](networkpolicy.md)
