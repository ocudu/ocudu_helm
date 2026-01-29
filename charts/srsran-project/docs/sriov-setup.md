# SR-IOV Setup Guide

SR-IOV (Single Root I/O Virtualization) provides high-performance network interfaces to pods. This is the recommended approach for production deployments.

## Prerequisites

- Host system supports SR-IOV
- Virtual Functions (VFs) configured on network cards
- VFs bound to DPDK-compatible driver (vfio-pci recommended)
- Kubernetes or k3s cluster deployed

## Required Components

1. **Multus CNI** - Enables multiple network interfaces
2. **SR-IOV CNI Plugin** - Handles VF attachment
3. **SR-IOV Device Plugin** - Exposes VFs as Kubernetes resources

## Setup Steps

### 1. Configure Virtual Functions on Host

```bash
# Identify your network device
lspci -nn | grep Ethernet

# Example: Configure 4 VFs on device 01:00.0
echo 4 > /sys/class/net/eth0/device/sriov_numvfs

# Bind VFs to vfio-pci driver
modprobe vfio-pci
echo "8086 154c" > /sys/bus/pci/drivers/vfio-pci/new_id  # Replace with your device ID
```

### 2. Deploy SR-IOV Components

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

### 3. Verify SR-IOV Resources

```bash
# Check if SR-IOV resources are available
kubectl get nodes -o json | jq '.items[].status.allocatable' | grep intel.com/intel_sriov

# Check node capacity
kubectl describe node <node-name> | grep -A 5 "Allocatable"

# Expected output should show:
#   intel.com/intel_sriov_netdevice: 4
```

### 4. Create SR-IOV Network Attachment

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

## Verification

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

## Troubleshooting

### VFs Not Showing Up

```bash
# Check VF configuration
ip link show
lspci | grep Virtual

# Verify driver binding
lspci -k -s <VF_BDF>
```

### Device Plugin Not Working

```bash
# Check device plugin logs
kubectl logs -n kube-system -l app=sriovdp --tail=50

# Verify ConfigMap
kubectl get configmap -n kube-system sriovdp-config -o yaml
```

### Pod Not Getting VF

```bash
# Check resource availability
kubectl describe node <node-name> | grep intel.com/intel_sriov

# Check pod events
kubectl describe pod <pod-name>
```

## See Also

- [Network Deployment Modes](network-modes.md) - SR-IOV vs hostNetwork
- [NetworkPolicy Configuration](networkpolicy.md) - Securing network traffic
