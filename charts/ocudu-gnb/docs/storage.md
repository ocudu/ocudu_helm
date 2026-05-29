# Storage Configuration

The chart supports two storage types for debugging logs: **PersistentVolumeClaim (PVC)** and **hostPath**. Choose based on your cluster environment.

## Storage Type Comparison

| Feature | PVC | hostPath |
|---------|-----|----------|
| **Best for** | Cloud environments | Bare-metal clusters |
| **Dynamic provisioning** | ✅ Yes (with StorageClass) | ❌ No |
| **Portability** | ✅ High (cluster-managed) | ⚠️ Node-specific |
| **Setup complexity** | Low (automatic) | Medium (manual paths) |
| **Production use** | ✅ Recommended | ✅ Acceptable |

## PVC Storage (Recommended for Cloud)

### Check Available StorageClasses

```bash
kubectl get storageclass
```

### Configuration with Default StorageClass

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: ""  # Use default StorageClass
    accessMode: ReadWriteOnce
    size: 10Gi
  mountPath: "/var/log/srs"
```

### Configuration with Specific StorageClass

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: "fast-ssd"  # Your StorageClass name
    accessMode: ReadWriteOnce
    size: 10Gi
  mountPath: "/var/log/srs"
```

### Configuration with Different Access Modes

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: "nfs"
    accessMode: ReadWriteMany  # For shared access
    size: 50Gi
  mountPath: "/var/log/srs"
```

## hostPath Storage (Bare-metal)

For bare-metal or when you need direct host access.

### Basic Configuration

```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/debugging-logs"
    type: DirectoryOrCreate
  mountPath: "/var/log/srs"
```

### Important Considerations

⚠️ **Node-specific**: Ensure the host path exists or can be created on all worker nodes where the pod may be scheduled.

⚠️ **Permissions**: The path must be writable by the container user.

⚠️ **Persistence**: Data persists on the node even after pod deletion.

### hostPath Types

```yaml
# Directory must exist
hostPath:
  path: "/mnt/data"
  type: Directory

# Create if doesn't exist  
hostPath:
  path: "/mnt/data"
  type: DirectoryOrCreate

# File must exist
hostPath:
  path: "/mnt/config/app.conf"
  type: File
```

## Disabling Persistent Storage

For testing or when logs aren't needed:

```yaml
persistence:
  enabled: false
```

**⚠️ Warning**: Logs will be lost when the pod restarts.

> **Note**: When `persistence.enabled: false`, the volume for debugging logs is not mounted. If your gNB config specifies `log.filename: /var/log/srs/debugging-logs/gnb.log`, the directory `/var/log/srs/debugging-logs/` won't exist. Either enable persistence or change the log path to `/var/log/srs/gnb.log` in your config.

## Common Scenarios

### Cloud Deployment (EKS, GKE, AKS)

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: ""  # Use cloud provider default
    size: 20Gi
```

### Bare-metal with Local Storage

```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/local-storage/gnb-logs"
    type: DirectoryOrCreate
```

### Bare-metal with Local Path Provisioner

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: "local-path"  # local-path-provisioner
    size: 10Gi
```

### Development/Testing

```yaml
persistence:
  enabled: false  # No persistence needed
```

## Troubleshooting

### PVC Stuck in Pending

```bash
# Check PVC status
kubectl get pvc -n <namespace>

# Check events
kubectl describe pvc <pvc-name> -n <namespace>

# Check StorageClass
kubectl get storageclass
```

**Common causes**:
- No StorageClass available
- No available storage on nodes
- Missing permissions for provisioner

### hostPath Permission Denied

```bash
# Check directory ownership on node
ls -la /mnt/debugging-logs

# Fix permissions (on node)
sudo chown 1000:1000 /mnt/debugging-logs
sudo chmod 755 /mnt/debugging-logs
```

### Pod Scheduled on Wrong Node (hostPath)

If using hostPath, ensure the pod is scheduled on the node with the path:

```yaml
nodeSelector:
  kubernetes.io/hostname: node-with-storage

# Or use nodeAffinity for more flexibility
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: storage
          operator: In
          values:
          - local-ssd
```

## Migration Between Storage Types

### From hostPath to PVC

1. Backup existing data from hostPath
2. Update values.yaml to use PVC
3. Upgrade the chart
4. Copy data to new PVC if needed

```bash
# Copy data from old pod to new
kubectl cp <old-pod>:/var/log/srs/logs ./backup
kubectl cp ./backup <new-pod>:/var/log/srs/logs
```

### From PVC to hostPath

1. Scale down deployment
2. Copy PVC data to host
3. Update values.yaml to use hostPath
4. Upgrade the chart

## See Also

- Kubernetes Storage Concepts: https://kubernetes.io/docs/concepts/storage/
- StorageClass Documentation: https://kubernetes.io/docs/concepts/storage/storage-classes/
