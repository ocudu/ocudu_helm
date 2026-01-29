# srsRAN Project CU/DU

A Helm chart for deploying the srsRAN Project 5G CU/DU (gNB)

## Node Requirements

Before deploying the srsRAN Project CU/DU on a node, ensure the following requirements are met:

1. **PTP4l and PHC2SYS**: These services must be running, and the local hardware clock must be synchronized. This ensures accurate communcation between CU/DU and RU.

2. **Interface Binding**: The interface connected to the Radio Unit (RU) must be bound to a DPDK-compatible driver such as `igb_uio` or `vfio-pci`. For detailed instructions on interface binding, please refer to the DPDK documentation at [DPDK Interface Binding Guide](https://doc.dpdk.org/guides/tools/devbind.html).

3. **Hugepages** (Optional): For using DPDK, it's required to configure hugepages on the node. The chart supports both 1Gi and 2Mi hugepages, but they are disabled by default. See the [Hugepages Configuration](#hugepages-configuration) section below for details.

## Network Deployment Modes

The gNB supports two network deployment modes with different characteristics:

### Mode 1: SR-IOV with CNI (Default - Production)

**Recommended for production deployments** with network isolation and security:

```yaml
network:
  hostNetwork: false  # Uses CNI network (default)

sriovConfig:
  enabled: true  # Enabled by default
  extendedResourceName: "intel.com/intel_sriov_netdevice"
  vfCount: 1

networkPolicy:
  enabled: true  # Optional, for traffic control
```

**Characteristics**:
- ✅ NetworkPolicy support for traffic control
- ✅ Better network isolation and security
- ✅ Multi-tenant friendly
- ✅ Production-grade networking
- ⚠️ Requires SR-IOV setup (see below)

**Use for**: Production deployments, regulated environments, multi-tenant clusters

### Mode 2: Host Network (Fallback - Convenience)

**For quick setup on bare-metal** when SR-IOV is not available:

```yaml
network:
  hostNetwork: true  # Uses host network namespace

sriovConfig:
  enabled: false  # Not needed with hostNetwork
  
# NetworkPolicy has no effect when hostNetwork: true
```

**Characteristics**:
- ✅ Simple setup, direct hardware access
- ✅ No SR-IOV device plugin needed
- ✅ Works immediately on bare-metal
- ⚠️ NetworkPolicy does NOT apply (bypasses pod networking)
- ⚠️ Less network isolation

**Use for**: Development, testing, bare-metal convenience deployments

## SR-IOV Setup Instructions

SR-IOV (Single Root I/O Virtualization) provides high-performance network interfaces to pods. This is the recommended approach for production deployments.

### Prerequisites

- Host system supports SR-IOV
- Virtual Functions (VFs) configured on network cards
- VFs bound to DPDK-compatible driver (vfio-pci recommended)
- Kubernetes or k3s cluster deployed

### SR-IOV Components Required

1. **Multus CNI** - Enables multiple network interfaces
2. **SR-IOV CNI Plugin** - Handles VF attachment
3. **SR-IOV Device Plugin** - Exposes VFs as Kubernetes resources

### Setup Steps

#### 1. Configure Virtual Functions on Host

```bash
# Identify your network device
lspci -nn | grep Ethernet

# Example: Configure 4 VFs on device 01:00.0
echo 4 > /sys/class/net/eth0/device/sriov_numvfs

# Bind VFs to vfio-pci driver
modprobe vfio-pci
echo "8086 154c" > /sys/bus/pci/drivers/vfio-pci/new_id  # Replace with your device ID
```

#### 2. Deploy SR-IOV Components

```bash
# Install Multus CNI
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml

# Install SR-IOV CNI
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/sriov-cni/master/images/sriov-cni-daemonset.yaml

# Install SR-IOV Device Plugin with ConfigMap
# Create ConfigMap for your device configuration
kubectl apply -f sriov-configmap.yaml
kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/sriov-network-device-plugin/master/deployments/sriovdp-daemonset.yaml
```

#### 3. Verify SR-IOV Resources

```bash
# Check if SR-IOV resources are available
kubectl get nodes -o json | jq '.items[].status.allocatable' | grep intel.com/intel_sriov

# Check node capacity
kubectl describe node <node-name> | grep -A 5 "Allocatable"

# Expected output should show:
#   intel.com/intel_sriov_netdevice: 4
```

#### 4. Create SR-IOV Network Attachment

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: sriov-net1
spec:
  config: '{
    "type": "sriov",
    "cniVersion": "0.3.1",
    "name": "sriov-network",
    "ipam": {
      "type": "host-local",
      "subnet": "10.56.217.0/24",
      "routes": [{
        "dst": "0.0.0.0/0"
      }],
      "gateway": "10.56.217.1"
    }
  }'
```

Apply the network attachment:
```bash
kubectl apply -f sriov-network-attachment.yaml
```

### Verifying SR-IOV Setup

Test with a simple pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sriov-test
  annotations:
    k8s.v1.cni.cncf.io/networks: sriov-net1
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "3600"]
    resources:
      requests:
        intel.com/intel_sriov_netdevice: '1'
      limits:
        intel.com/intel_sriov_netdevice: '1'
```

Check the pod has the SR-IOV interface:
```bash
kubectl exec sriov-test -- ip link show
```

### Troubleshooting SR-IOV

**VFs not showing up**:
```bash
# Check VF configuration
ip link show
lspci | grep Virtual

# Verify driver binding
lspci -k -s <VF_BDF>
```

**Device plugin not working**:
```bash
# Check device plugin logs
kubectl logs -n kube-system -l app=sriovdp --tail=50

# Verify ConfigMap
kubectl get configmap -n kube-system sriovdp-config -o yaml
```

**Pod not getting VF**:
```bash
# Check resource availability
kubectl describe node <node-name> | grep intel.com/intel_sriov

# Check pod events
kubectl describe pod <pod-name>
```

## Configuration of the srsRAN Project CU/DU

The configuration file for the srsran Project CU/DU is located in the root directory of this Helm chart, its named `gnb-config.yml`. To configure the application, refer to the documentation provided at [srsRAN Project User Manual](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/running.html). The config file will be mounted as a ConfigMap into the container on runtime.

## Hugepages Configuration

Hugepages are **optional** but recommended for DPDK-based deployments to achieve optimal performance. The chart automatically detects and configures hugepage volumes when you define `hugepages-1Gi` or `hugepages-2Mi` in your resource limits or requests.

### Checking Cluster Support

Before using hugepages, verify your cluster has them configured:

```bash
# Check if hugepages are available on cluster nodes
kubectl get nodes -o json | jq '.items[].status.capacity | select(.["hugepages-1Gi"] or .["hugepages-2Mi"])'

# Alternative: Check on the node directly
cat /proc/meminfo | grep HugePages
```

### Using Hugepages

Simply define hugepages in your resource configuration. The chart will automatically create the necessary volumes and mounts:

**With 1Gi hugepages (recommended for DPDK):**
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

**With 2Mi hugepages (alternative):**
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

### Deploying Without Hugepages

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

**Note**: If you define hugepages in resources but your cluster doesn't have them configured, the deployment will fail with a scheduling error. Always verify cluster support first.

## NetworkPolicy Configuration

NetworkPolicy provides network-level security by controlling traffic to and from the gNB pod. **This only works when `hostNetwork: false`** (SR-IOV mode).

### Checking NetworkPolicy Support

```bash
# Check if your cluster supports NetworkPolicy
kubectl api-versions | grep networking.k8s.io/v1

# Check if a NetworkPolicy controller is installed
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'
```

### Enabling NetworkPolicy

```yaml
network:
  hostNetwork: false  # Required for NetworkPolicy

networkPolicy:
  enabled: true

  ingress:
    fiveGCore:
      enabled: true
      from:
        - podSelector:
            matchLabels:
              app: open5gs
        - ipBlock:
            cidr: 10.0.0.0/8  # Your 5G core network CIDR

    monitoring:
      enabled: true
      from:
        - namespaceSelector:
            matchLabels:
              name: monitoring

  egress:
    fiveGCore:
      enabled: true
      to:
        - podSelector:
            matchLabels:
              app: open5gs
        - ipBlock:
            cidr: 10.0.0.0/8
```

### Custom Network Rules

Add custom ingress/egress rules as needed:

```yaml
networkPolicy:
  ingress:
    custom:
      - from:
          - podSelector:
              matchLabels:
                app: custom-monitoring
        ports:
          - protocol: TCP
            port: 9090

  egress:
    custom:
      - to:
          - podSelector:
              matchLabels:
                app: external-service
        ports:
          - protocol: TCP
            port: 8080
```

### Important Notes

⚠️ **NetworkPolicy Limitations**:
- Only works when `hostNetwork: false` (SR-IOV mode)
- When `hostNetwork: true`, pod uses host network and bypasses NetworkPolicy
- Requires a NetworkPolicy controller (Calico, Cilium, Weave, etc.)
- Not all clusters have NetworkPolicy support enabled

### Default Allowed Traffic

When NetworkPolicy is enabled, the following traffic is allowed by default:
- **Ingress**: From 5G Core (N2/N3), monitoring systems, O1 management (if enabled)
- **Egress**: To 5G Core, DNS, monitoring systems

All other traffic is denied unless explicitly allowed.

## Storage Configuration

The chart supports two storage types for debugging logs: **PersistentVolumeClaim (PVC)** and **hostPath**. Choose based on your cluster environment.

### Storage Type Comparison

| Feature | PVC | hostPath |
|---------|-----|----------|
| **Best for** | Cloud environments | Bare-metal clusters |
| **Dynamic provisioning** | ✅ Yes (with StorageClass) | ❌ No |
| **Portability** | ✅ High (cluster-managed) | ⚠️ Node-specific |
| **Setup complexity** | Low (automatic) | Medium (manual paths) |
| **Production use** | ✅ Recommended | ✅ Acceptable |

### Using PVC Storage (Recommended for Cloud)

Check available StorageClasses in your cluster:

```bash
kubectl get storageclass
```

Configure PVC storage in `values.yaml`:

```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: ""  # Use default StorageClass
    accessMode: ReadWriteOnce
    size: 10Gi
  mountPath: "/tmp"
```

**With specific StorageClass:**
```yaml
persistence:
  enabled: true
  type: pvc
  pvc:
    storageClassName: "fast-ssd"  # Your StorageClass name
    accessMode: ReadWriteOnce
    size: 10Gi
```

### Using hostPath Storage (Bare-metal)

For bare-metal or when you need direct host access:

```yaml
persistence:
  enabled: true
  type: hostPath
  hostPath:
    path: "/mnt/debugging-logs"
    type: DirectoryOrCreate
  mountPath: "/tmp"
```

**Important**: Ensure the host path exists or can be created on all worker nodes where the pod may be scheduled.

### Disabling Persistent Storage

For testing or when logs aren't needed:

```yaml
persistence:
  enabled: false
```

**Warning**: Logs will be lost when the pod restarts.

## Choosing a Container Image

Select the appropriate container image based on your CPU flags and architecture. We provide images with the following combinations:

- CPU Architectures: arm64 and amd64
- Operating System: Ubuntu 22.04
- CPU Flags: AVX512, AVX2, NEON

All images can be found in our [Docker Hub Repo](https://hub.docker.com/u/softwareradiosystems).

We encourage every user to build their own container images to not be limited to the above listed images. Therefore, we provide the Dockerfiles we use as well in this repository.

## Installing the Chart

To install the chart with the release name `srsran-project`:

```console
cd charts/srsran-project
helm install srsran-project ./
```

## Uninstalling the Chart

To uninstall/delete the srsran-project deployment:

```console
helm delete srsran-project
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

### Chart Parameters

| Parameter | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Pod affinity configuration |
| annotations | object | `{}` | Annotations for the Deployment |
| securityContext | object | `{}` | Container security context (allowPrivilegeEscalation, etc.) |
| fullnameOverride | string | `""` | Overrides the chart's computed fullname |
| interfaceName | string | `{}` | Name of the interface to be used for ptp4l |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.pullSecrets | list | `[]` | Image pull secrets |
| image.repository | string | `"srsran/linuxptp-agent"` | Image repository |
| image.tag | string | `""` | Image tag |
| nameOverride | string | `""` | Overrides the chart's name |
| nodeSelector | object | `{}` | nodeSelector configuration |
| podAnnotations | object | `{}` | Annotations for the Deployment Pods |
| podSecurityContext | object | `{}` | Pod security context (runAsUser, etc.) |
| resources | object | `{}` | Resource limits and requests config |
| serviceAccount.annotations | object | `{}` | Annotations for service account |
| serviceAccount.create | bool | `true` | Toggle to create ServiceAccount |
| serviceAccount.name | string | `nil` | Service account name |
| tolerations | list | `[]` | Tolerations applied to Pods |
| network | object | `[]` | Container to configure hostNetwork  |
| o1 | object | `[]` | Container to configure O1 |
| o1_config | object | `[]` | Container to the O1 config file |
| debugging | object | `[]` | Container to configure debugging options |
| service | object | `[]` | Container to configure debugging LoadBalancer options |
| config | object | `[]` | Container to configure srsRAN CU/DU application |

For more information about the values of the config sectoin please refer to the [srsRAN Project Configuration Reference](https://docs.srsran.com/projects/project/en/latest/user_manuals/source/config_ref.html).
