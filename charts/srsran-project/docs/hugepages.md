# Hugepages Configuration

Hugepages are **optional** but recommended for DPDK-based deployments to achieve optimal performance. The chart automatically detects and configures hugepage volumes when you define `hugepages-1Gi` or `hugepages-2Mi` in your resource limits or requests.

## Checking Cluster Support

Before using hugepages, verify your cluster has them configured:

```bash
# Check if hugepages are available on cluster nodes
kubectl get nodes -o json | jq '.items[].status.capacity | select(.["hugepages-1Gi"] or .["hugepages-2Mi"])'

# Alternative: Check on the node directly
cat /proc/meminfo | grep HugePages
```

## Using Hugepages

Simply define hugepages in your resource configuration. The chart will automatically create the necessary volumes and mounts.

### With 1Gi Hugepages (Recommended for DPDK)

```yaml
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

### With 2Mi Hugepages (Alternative)

```yaml
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

## Deploying Without Hugepages

Simply omit hugepages from your resource configuration:

```yaml
resources:
  limits:
    cpu: 12
    memory: 16Gi
  requests:
    cpu: 12
    memory: 16Gi
```

## How It Works

The chart uses auto-detection to configure hugepages:

1. **Detection**: Chart checks if `hugepages-1Gi` or `hugepages-2Mi` is defined in resources
2. **Volume Creation**: If detected, creates an emptyDir volume with the appropriate medium
3. **Mounting**: Automatically mounts the volume to `/hugepages-1Gi` or `/hugepages-2Mi`

No additional configuration flags needed!

## Configuring Hugepages on Nodes

If your cluster doesn't have hugepages configured, you'll need to set them up on the nodes.

### Check Current Configuration

```bash
# On the node
cat /proc/meminfo | grep HugePages
```

### Configure 1Gi Hugepages

```bash
# Reserve 8x 1Gi hugepages
echo 8 > /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages

# Make persistent (add to /etc/sysctl.conf)
echo "vm.nr_hugepages = 8" >> /etc/sysctl.conf
sysctl -p
```

### Configure 2Mi Hugepages

```bash
# Reserve 4096x 2Mi hugepages (8Gi total)
echo 4096 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

# Make persistent
echo "vm.nr_hugepages = 4096" >> /etc/sysctl.conf
sysctl -p
```

## Troubleshooting

### Deployment Fails with "Insufficient hugepages-1Gi"

**Cause**: Hugepages defined in resources but not available on nodes.

**Solution**:
1. Check node capacity: `kubectl describe node <node-name> | grep hugepages`
2. Either configure hugepages on nodes (see above)
3. Or remove hugepages from resources configuration

### How Much Hugepages Do I Need?

For DPDK applications:
- **Minimum**: 2Gi of 1Gi hugepages (2 pages)
- **Recommended**: 4-8Gi of 1Gi hugepages
- Consider DPDK buffer pools, packet mbuf sizes, and traffic load

Example calculation:
```
DPDK mempool size + Packet buffers + Safety margin
= 1Gi + 512Mi + 512Mi
= 2Gi (use 2x 1Gi hugepages)
```

### Verifying Hugepages in Pod

```bash
# Check if hugepages are mounted
kubectl exec <pod-name> -- df -h | grep hugepages

# Check hugepage usage inside pod
kubectl exec <pod-name> -- cat /proc/meminfo | grep Huge
```

## Important Notes

⚠️ **Warning**: If you define hugepages in resources but your cluster doesn't have them configured, the deployment will fail with a scheduling error. Always verify cluster support first.

✅ **Best Practice**: Start without hugepages and add them later if needed for performance optimization.

## See Also

- DPDK documentation on hugepages: https://doc.dpdk.org/guides/linux_gsg/sys_reqs.html#use-of-hugepages
