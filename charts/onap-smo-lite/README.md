# ONAP SMO Lite

> **⚠️ Integration PoC - Demo Only - No Support Provided**
> 
> This chart is provided **as-is** for integration testing and demonstration purposes only.
> It contains hardcoded configurations and is not intended for production use.
> Deploy as-is with no expectation of support or maintenance.

## Overview

A lightweight ONAP Service Management and Orchestration (SMO) stack for O1 management interface demonstrations with srsRAN gNodeB.

This chart deploys a minimal ONAP SMO environment consisting of:
- **SDNC Web UI** - Web interface for SDN-R controller
- **SDN-R Controller** - OpenDaylight-based RAN management controller
- **Elasticsearch** - Database backend for SDN-R
- **Kafka + Zookeeper** - Event messaging backbone
- **VES Collector** - ONAP VES (Virtual Event Streaming) event collector
- **Kafka UI** - Web interface for Kafka topic inspection (optional)

## Prerequisites

- Kubernetes >= 1.24.0
- Helm >= 3.0.0
- Sufficient cluster resources (minimum 4 CPU cores, 8GB RAM recommended)

### ⚠️ Mandatory Configuration: Cluster Domain

**You MUST configure `global.clusterDomain` to match your Kubernetes cluster's DNS zone.**

By default, the chart uses `srsk8s.bcn` which is specific to the development environment. 
Most Kubernetes clusters use `cluster.local` as the default domain.

**Find your cluster domain:**
```bash
# Check your cluster's DNS configuration
kubectl get configmap coredns -n kube-system -o yaml | grep kubernetes

# Common values:
# - cluster.local (default Kubernetes)
# - your-custom-domain (custom installations)
```

**Configure before installation:**
```bash
# Option 1: Via command line
helm install onap-smo-lite ./charts/onap-smo-lite \
  --set global.clusterDomain="cluster.local" \
  --namespace onap --create-namespace

# Option 2: Via values file
# Create custom-values.yaml with:
#   global:
#     clusterDomain: "cluster.local"
helm install onap-smo-lite ./charts/onap-smo-lite \
  -f custom-values.yaml \
  --namespace onap --create-namespace
```

## Installation

### Basic Installation

**Important**: Set `global.clusterDomain` to match your cluster (see Prerequisites above).

```bash
# Install with cluster.local (most common)
helm install onap-smo-lite ./charts/onap-smo-lite \
  --set global.clusterDomain="cluster.local" \
  --namespace onap \
  --create-namespace
```

### Access the Web Interfaces

After installation, access the UIs via NodePort services:

- **SDN-R Web UI**: `http://<node-ip>:30080` (default credentials: root/root)
- **Kafka UI**: `http://<node-ip>:30085` (if enabled)

### Verifying Installation

```bash
# Check all pods are running
kubectl get pods -n onap

# View services
kubectl get svc -n onap
```

Expected pods: sdnc-web, sdnr, sdnrdb (Elasticsearch), kafka, zookeeper, ves-collector, kafka-ui (if enabled)

## Configuration

### Key Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| **`global.clusterDomain`** | **Kubernetes cluster DNS zone** | `srsk8s.bcn` | **✅ YES** |
| `sdncWeb.service.nodePort` | NodePort for SDN-R Web UI access | `30080` | No |
| `sdnr.adminCredentials.username` | SDN-R admin username | `root` | No |
| `sdnr.adminCredentials.password` | SDN-R admin password | `root` | No |
| `sdnrdb.persistence.enabled` | Enable persistent storage for Elasticsearch | `false` | No |
| `kafka.auth.enabled` | Enable Kafka authentication | `false` | No |
| `kafkaUi.enabled` | Deploy Kafka UI | `true` | No |
| `kafkaUi.service.nodePort` | NodePort for Kafka UI access | `30085` | No |
| `vesCollector.credentials.username` | VES Collector username | `sample1` | No |
| `vesCollector.credentials.password` | VES Collector password | `sample1` | No |

### Mandatory Configuration

**`global.clusterDomain`** - This parameter MUST be set to match your Kubernetes cluster's DNS zone.

The chart uses this to construct Fully Qualified Domain Names (FQDNs) for inter-service communication:
- SDNC Web → SDN-R Controller
- SDN-R → Elasticsearch Database
- Kafka broker advertised listeners
- VES Collector → Kafka
- SDN-R Registrar → Kafka

**Common values:**
- `cluster.local` - Standard Kubernetes default
- `your-domain.com` - Custom cluster installations

**Example:**
```bash
# For standard Kubernetes clusters
--set global.clusterDomain="cluster.local"
```

See [`values.yaml`](values.yaml) for the complete list of configuration options.

## Uninstalling

```bash
helm uninstall onap-smo-lite --namespace onap
```

## Troubleshooting

### Pods Not Starting

Check pod status and logs:
```bash
kubectl get pods -n onap
kubectl describe pod <pod-name> -n onap
kubectl logs <pod-name> -n onap
```

### Service Connection Issues

Verify services are accessible:
```bash
kubectl get svc -n onap
```

Ensure the hardcoded cluster domain in `values.yaml` matches your cluster's DNS zone.

### Elasticsearch Issues

If sdnrdb (Elasticsearch) fails to start, check resource limits and ensure single-node discovery mode is enabled.

## Integration with srsRAN gNodeB

To integrate with srsRAN O1 interface:

1. Deploy this chart in a namespace (e.g., `onap`)
2. Configure srsRAN gNodeB O1 settings to point to:
   - NETCONF server: SDN-R NETCONF port
   - VES Collector: `http://onap-smo-ves-collector.onap.svc.cluster.local:8443`
3. Access SDN-R Web UI to view connected network functions

Refer to srsRAN documentation for O1 configuration details.

## Support

**This chart is provided as-is with no support.** It is intended solely for integration testing and demonstrations. For production ONAP deployments, refer to official ONAP documentation.
