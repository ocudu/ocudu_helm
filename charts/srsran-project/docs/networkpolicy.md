# NetworkPolicy Configuration

NetworkPolicy provides network-level security by controlling traffic to and from the gNB pod.

**⚠️ Important**: NetworkPolicy only works when `hostNetwork: false` (SR-IOV mode). When `hostNetwork: true`, the pod uses the host's network namespace and bypasses NetworkPolicy.

## Checking Support

### Verify NetworkPolicy API

```bash
# Check if your cluster supports NetworkPolicy
kubectl api-versions | grep networking.k8s.io/v1
```

### Verify NetworkPolicy Controller

```bash
# Check if a NetworkPolicy controller is installed
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'
```

Common NetworkPolicy controllers:
- Calico
- Cilium
- Weave Net
- Antrea

## Basic Configuration

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

## Custom Rules

### Custom Ingress Rules

Add additional services that can access the gNB:

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
      - from:
          - namespaceSelector:
              matchLabels:
                name: external-tools
          - podSelector:
              matchLabels:
                app: debug-tool
        ports:
          - protocol: TCP
            port: 22
```

### Custom Egress Rules

Add additional destinations the gNB can reach:

```yaml
networkPolicy:
  egress:
    custom:
      - to:
          - podSelector:
              matchLabels:
                app: external-api
        ports:
          - protocol: TCP
            port: 8080
      - to:
          - ipBlock:
              cidr: 192.168.1.0/24
        ports:
          - protocol: TCP
            port: 443
```

## Default Allowed Traffic

When NetworkPolicy is enabled, the following traffic is allowed by default:

### Ingress (Incoming)
- **5G Core (N2/N3)**: SCTP port 38412, UDP port 2152
- **Monitoring**: From monitoring namespace (when metricsService.enabled)
- **Management (O1)**: NETCONF port (when o1.enable_srs_o1 is true)

### Egress (Outgoing)
- **5G Core**: To AMF/UPF
- **DNS**: UDP/TCP port 53 (always allowed)
- **Monitoring**: To InfluxDB and VES collector

All other traffic is **denied** unless explicitly allowed.

## Important Limitations

⚠️ **NetworkPolicy Limitations**:
- Only works when `hostNetwork: false` (SR-IOV mode)
- When `hostNetwork: true`, pod uses host network and bypasses NetworkPolicy
- Requires a NetworkPolicy controller (Calico, Cilium, Weave, etc.)
- Not all clusters have NetworkPolicy support enabled
- May require cluster-specific configuration

## Debugging NetworkPolicy

### Check NetworkPolicy is Created

```bash
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### Test Connectivity

```bash
# From another pod, test if gNB is reachable
kubectl run test-pod --rm -it --image=busybox -- sh
# Inside the pod:
nc -zv <gnb-pod-ip> 38412
```

### Check NetworkPolicy Controller Logs

```bash
# Calico
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50

# Cilium
kubectl logs -n kube-system -l k8s-app=cilium --tail=50
```

## Examples

### Allow All Traffic (Development)

```yaml
networkPolicy:
  enabled: false  # Disable NetworkPolicy
```

### Strict Production Policy

```yaml
networkPolicy:
  enabled: true
  
  ingress:
    fiveGCore:
      enabled: true
      from:
        - ipBlock:
            cidr: 10.0.0.100/32  # Specific AMF IP
    
    monitoring:
      enabled: true
      from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
          podSelector:
            matchLabels:
              app: telegraf
    
    management:
      enabled: true
      from:
        - ipBlock:
            cidr: 10.0.1.0/24  # Management network only
  
  egress:
    fiveGCore:
      enabled: true
      to:
        - ipBlock:
            cidr: 10.0.0.0/24  # Core network only
    
    monitoring:
      enabled: true
      to:
        - namespaceSelector:
            matchLabels:
              name: monitoring
```

## See Also

- [Network Deployment Modes](network-modes.md) - SR-IOV vs hostNetwork
- [SR-IOV Setup Guide](sriov-setup.md) - Configure SR-IOV for NetworkPolicy support
