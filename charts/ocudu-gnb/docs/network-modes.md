# Network Deployment Modes

The gNB supports two network deployment modes with different characteristics.

## Mode 1: SR-IOV with CNI (Default - Production)

**Recommended for production deployments** with network isolation and security.

### Configuration

```yaml
network:
  hostNetwork: false  # Uses CNI network (default), use SR-IOV Device Plugin for OFH interface

sriovConfig:
  enabled: true  # Enabled by default
  extendedResourceName: "intel.com/intel_sriov_netdevice"
  vfCount: 1

networkPolicy:
  enabled: true  # Optional, for traffic control

# Security context for SR-IOV Device Plugin enabled
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

### Characteristics

- ✅ NetworkPolicy support for traffic control
- ✅ Better network isolation and security
- ✅ Multi-tenant friendly
- ✅ Production-grade networking
- ⚠️ Requires SR-IOV setup (see [SR-IOV Setup Guide](sriov-setup.md))

### Use Cases

- Production deployments
- Regulated environments
- Multi-tenant clusters
- When network isolation is required

## Mode 2: Host Network (Fallback - Convenience)

**For quick setup on bare-metal** when SR-IOV is not available.

### Configuration

```yaml
network:
  hostNetwork: true  # Uses host network namespace

sriovConfig:
  enabled: false  # Not needed with hostNetwork

# NetworkPolicy has no effect when hostNetwork: true

# Security context for SR-IOV Device Plugin disabled
securityContext:
  capabilities:
    add: ["SYS_NICE", "NET_ADMIN"]
  privileged: true
```

### Characteristics

- ✅ Simple setup, direct hardware access
- ✅ No SR-IOV device plugin needed
- ✅ Works immediately on bare-metal
- ⚠️ NetworkPolicy does NOT apply (bypasses pod networking)
- ⚠️ Less network isolation

### Use Cases

- Development and testing
- Bare-metal convenience deployments
- When SR-IOV is not available
- Quick prototyping

## Comparison

| Feature | SR-IOV Mode | Host Network Mode |
|---------|-------------|-------------------|
| **Setup Complexity** | Medium (requires SR-IOV) | Low (works immediately) |
| **NetworkPolicy Support** | ✅ Yes | ❌ No |
| **Network Isolation** | ✅ High | ⚠️ Low |
| **Performance** | ✅ High | ✅ High |
| **Production Ready** | ✅ Yes | ⚠️ For specific cases |
| **Multi-tenant Safe** | ✅ Yes | ❌ No |
| **DPDK Driver** | vfio-pci (recommended) | igb_uio (kernel) |
| **Privileged Mode** | ❌ Not required | ✅ Required |

## Choosing the Right Mode

**Use SR-IOV Mode (Default) if:**
- Deploying in production
- Network isolation is required
- Using NetworkPolicy for security
- Running in multi-tenant environment

**Use Host Network Mode if:**
- Rapid prototyping or testing
- SR-IOV is not available
- Running on bare-metal for development
- Network isolation is not a concern

## See Also

- [SR-IOV Setup Guide](sriov-setup.md) - Complete SR-IOV installation
- [NetworkPolicy Configuration](networkpolicy.md) - Network security setup
