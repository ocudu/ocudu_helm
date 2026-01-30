# OCUDU Kubernetes Helm Charts

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Kubernetes Helm charts for deploying OCUDU 5G Radio Access Network (RAN) components and supporting infrastructure.

## Available Charts

### Production Chart

| Chart | Version | Description | Status |
|-------|---------|-------------|--------|
| [ocudu-gnb](charts/ocudu-gnb/) | 3.0.x | 5G gNB (CU/DU Combined) with O1, DPDK, SR-IOV support | 🟢 **Production Ready** |

**This is the only Helm Chart under active maintenance**

### PoC/Demo Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [linuxptp](charts/linuxptp/) | 2.0.x | PTP time synchronization (ptp4l, phc2sys, ts2phc) |
| [grafana-ocudu](charts/grafana-ocudu/) | 2.0.x | Monitoring stack (Grafana + InfluxDB3 + Telegraf) |
| [influxdb3](charts/influxdb3/) | 2.0.x | InfluxDB3 time-series database |
| [onap-smo-lite](charts/onap-smo-lite/) | 1.0.x | ONAP SMO components for O1 management |
| [rt-tests](charts/rt-tests/) | 2.0.x | Real-time performance testing tools |
| [ru_emulator](charts/ru_emulator/) | 2.0.x | Radio Unit (O-RU) emulator for testing |
| [tuned](charts/tuned/) | 1.0.x | System tuning profiles for low-latency |

⚠️ **PoC/Demo Status** means:
- Intended for **development, testing, and proof-of-concept deployments only**
- May use insecure defaults (privileged mode, anonymous access, etc.)
- Minimal security hardening
- **Not actively maintained**
- **Not intended for production use**

## Usage

### Prerequisites

- Kubernetes cluster (>= 1.24.0)
- [Helm](https://helm.sh) 3.x installed
- `kubectl` configured to access your cluster

### Installation

Each chart has its own README with detailed installation instructions. General pattern:

```bash
# Add the chart repository (if using a Helm repository)
helm repo add ocudu https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/

# Install a chart
helm install my-release ocudu/<chart-name> \
  --namespace <namespace> \
  --create-namespace

# For production deployments, use custom values
helm install my-gnb ocudu/ocudu-gnb \
  -f my-production-values.yaml \
  --namespace ran-prod \
  --create-namespace
```

### Documentation

Refer to each chart's README for detailed configuration options:
- [ocudu-gnb](charts/ocudu-gnb/README.md)
- [linuxptp](charts/linuxptp/README.md)
- [grafana-ocudu](charts/grafana-ocudu/README.md)
- [influxdb3](charts/influxdb3/README.md)
- [onap-smo-lite](charts/onap-smo-lite/README.md)
- [rt-tests](charts/rt-tests/README.md)
- [ru_emulator](charts/ru_emulator/README.md)
- [tuned](charts/tuned/README.md)

## Container Images

Container images are available in the GitLab Container Registry:
- **Chart images**: https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/container_registry
- **Split 7.2 images** (ru_emulator & ocudu-gnb): https://gitlab.com/ocudu/ocudu/container_registry

## License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
