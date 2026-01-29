# Security Configuration Guide

This guide covers security aspects of deploying the srsRAN CU/DU Helm chart, including Pod Security Standards, RBAC, security contexts, and Pod Disruption Budgets.

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

The srsRAN gNB requires specific Linux capabilities for real-time performance and hardware access:

- `IPC_LOCK` - Lock memory pages for DPDK
- `SYS_ADMIN` - Access DPDK devices
- `SYS_RAWIO` - Direct I/O operations
- `NET_RAW` - Raw socket access
- `SYS_NICE` - Real-time CPU scheduling

These capabilities are not permitted under the Restricted PSS profile.

### Recommended Configuration

**For Production (Baseline PSS):**

Use SR-IOV mode with non-privileged security context:

```yaml
network:
  hostNetwork: false

sriovConfig:
  enabled: true

securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    add:
      - IPC_LOCK
      - SYS_ADMIN
      - SYS_RAWIO
      - NET_RAW
      - SYS_NICE
```

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

### Verifying RBAC

Check what the service account can do:

```bash
# Check permissions
kubectl auth can-i get configmaps \
  --as=system:serviceaccount:srsran:srsadmin-gnb \
  -n srsran

# List RBAC resources
kubectl get role,rolebinding -n srsran
kubectl describe role srsadmin-gnb -n srsran
```

---

## Security Contexts

The chart supports two security context configurations based on the deployment mode.

### Mode 1: SR-IOV with vfio-pci (Recommended)

**Use when**: `hostNetwork: false` and `sriovConfig.enabled: true`

```yaml
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    add:
      - IPC_LOCK      # Memory locking for DPDK
      - SYS_ADMIN     # DPDK device access
      - SYS_RAWIO     # Direct I/O operations
      - NET_RAW       # Raw socket access
      - SYS_NICE      # Real-time CPU scheduling
```

**Advantages:**
- ✅ No privileged mode required
- ✅ Compatible with Pod Security Baseline
- ✅ Better security isolation
- ✅ NetworkPolicy support

**Requirements:**
- vfio-pci driver loaded
- IOMMU enabled in BIOS
- SR-IOV virtual functions configured

See [network-modes.md](network-modes.md) and [sriov-setup.md](sriov-setup.md) for detailed setup.

### Mode 2: Host Network with igb_uio (Fallback)

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

**⚠️ Warning**: Only use this mode for development or when SR-IOV is not available.

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

### Production Recommendation

For production deployments, always use `unhealthyPodEvictionPolicy: AlwaysAllow`.

This ensures:
- ✅ Cluster operability during maintenance
- ✅ Unhealthy pods don't block upgrades
- ✅ Self-healing capabilities work correctly

### Disabling PDB

Not recommended for production, but possible:

```yaml
podDisruptionBudget:
  enabled: false
```

### Verifying PDB

```bash
# Check PDB status
kubectl get pdb -n srsran
kubectl describe pdb srsran-project-cudu-chart -n srsran

# During node drain, check if PDB is respected
kubectl drain <node-name> --ignore-daemonsets
```

---

## Namespace Security

### Pod Security Standards Labels

Apply PSS labels to your namespace based on the deployment mode:

#### For Privileged Mode (hostNetwork: true)

```bash
kubectl create namespace srsran
kubectl label namespace srsran \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
```

#### For Baseline Mode (SR-IOV, hostNetwork: false)

```bash
kubectl create namespace srsran
kubectl label namespace srsran \
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
kubectl create namespace srsran
kubectl label namespace srsran pod-security.kubernetes.io/enforce=baseline
```

### 7. Regular Security Audits

```bash
# Check security contexts
kubectl get pod -n srsran -o jsonpath='{.items[*].spec.containers[*].securityContext}'

# Verify RBAC
kubectl auth can-i --list --as=system:serviceaccount:srsran:srsadmin-gnb -n srsran

# Check NetworkPolicies
kubectl get networkpolicy -n srsran
```

---

## Troubleshooting

### Pod Fails to Start (Security Context Issues)

**Symptom**: Pod in `CreateContainerError` or `CrashLoopBackOff`

**Check**:
```bash
kubectl describe pod <pod-name> -n srsran
kubectl logs <pod-name> -n srsran
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
  --as=system:serviceaccount:srsran:srsadmin-gnb -n srsran
```

**Solution**: Verify RBAC is enabled and service account is created:
```bash
kubectl get sa,role,rolebinding -n srsran
```

### Node Drain Blocked by PDB

**Symptom**: `kubectl drain` hangs or reports PDB violation

**Check**:
```bash
kubectl get pdb -n srsran
kubectl describe pdb <pdb-name> -n srsran
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
