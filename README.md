# OCUDU Kubernetes Helm Charts

[![License: BSD 3-Clause Open MPI](https://img.shields.io/badge/License-BSD%203--Clause%20Open%20MPI-blue.svg)](LICENSE)

Kubernetes Helm charts for deploying OCUDU 5G Radio Access Network (RAN) components and supporting infrastructure.

## Available Charts

### OCUDU Helm Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [ocudu-gnb](charts/ocudu-gnb/) | 3.7.x | 5G gNB (CU/DU Combined) with O1, DPDK, SR-IOV support |
| [ocudu-cu](charts/ocudu-cu/) | 1.2.x | 5G CU (Central Unit) with N2/N3/F1 services |
| [ocudu-du](charts/ocudu-du/) | 1.2.x | 5G DU (Distributed Unit) with F1, SR-IOV, DPDK support |

### Infrastructure Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [linuxptp](charts/linuxptp/) | 2.0.x | PTP time synchronization (ptp4l, phc2sys, ts2phc) |
| [grafana-ocudu](charts/grafana-ocudu/) | 2.0.x | Monitoring stack (Grafana + InfluxDB3 + Telegraf) |
| [influxdb3](charts/influxdb3/) | 2.0.x | InfluxDB3 time-series database |
| [onap-smo-lite](charts/onap-smo-lite/) | 1.0.x | ONAP SMO components for O1 management |
| [rt-tests](charts/rt-tests/) | 2.0.x | Real-time performance testing tools |
| [ru_emulator](charts/ru_emulator/) | 2.0.x | Radio Unit (O-RU) emulator for testing |
| [tuned](charts/tuned/) | 1.0.x | System tuning profiles for low-latency |

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

# Install with custom values
helm install my-gnb ocudu/ocudu-gnb \
  -f my-values.yaml \
  --namespace ran \
  --create-namespace
```

### Documentation

Refer to each chart's README for detailed configuration options:
- [ocudu-gnb](charts/ocudu-gnb/README.md)
- [ocudu-cu](charts/ocudu-cu/README.md)
- [ocudu-du](charts/ocudu-du/README.md)
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

This project is licensed under the BSD 3-Clause Open MPI variant License – see the LICENSE file for details.
Portions of this software may implement 3GPP specifications, which may be subject to additional licensing requirements.
