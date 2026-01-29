# srsRAN Kubernetes Helm Charts

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

Kubernetes Helm charts for deploying srsRAN 5G Radio Access Network (RAN) components and supporting infrastructure.

## Available Charts

### Production Chart

| Chart | Version | Description | Status |
|-------|---------|-------------|--------|
| [srsran-project](charts/srsran-project/) | 2.3.x | 5G CU/DU (gNodeB) with O1, DPDK, SR-IOV support | 🟢 **Production Ready** |

**This is the only Helm Chart under active maintenance**

### PoC/Demo Charts

| Chart | Version | Description |
|-------|---------|-------------|
| [linuxptp](charts/linuxptp/) | 1.3.x | PTP time synchronization (ptp4l, phc2sys, ts2phc) |
| [grafana-srsran](charts/grafana-srsran/) | 1.3.x | Monitoring stack (Grafana + InfluxDB3 + Telegraf) |
| [influxdb3](charts/influxdb3/) | 1.1.x | InfluxDB3 time-series database |
| [onap-smo-lite](charts/onap-smo-lite/) | 0.3.x | ONAP SMO components for O1 management |
| [rt-tests](charts/rt-tests/) | 1.0.x | Real-time performance testing tools |
| [ru_emulator](charts/ru_emulator/) | 1.2.x | Radio Unit (O-RU) emulator for testing |
| [tuned](charts/tuned/) | 0.5.x | System tuning profiles for low-latency |

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
helm repo add srsran https://github.com/srsran/srsRAN_Project_helm/

# Install a chart
helm install my-release srsran/<chart-name> \
  --namespace <namespace> \
  --create-namespace

# For production deployments, use custom values
helm install my-gnb srsran/srsran-project \
  -f my-production-values.yaml \
  --namespace ran-prod \
  --create-namespace
```

### Documentation

Refer to each chart's README for detailed configuration options:
- [srsran-project](charts/srsran-project/README.md) - **Start here for production deployments**
- [linuxptp](charts/linuxptp/README.md)
- [grafana-srsran](charts/grafana-srsran/README.md)
- [influxdb3](charts/influxdb3/README.md)
- [onap-smo-lite](charts/onap-smo-lite/README.md)
- [rt-tests](charts/rt-tests/README.md)
- [ru_emulator](charts/ru_emulator/README.md)
- [tuned](charts/tuned/README.md)

## Docker images

Every srsRAN Project release is accompanied by pre-built Docker images, which can be found on [Docker Hub](https://hub.docker.com/u/softwareradiosystems). The Dockerfiles utilized are located in the [srsRAN Project repository](https://github.com/srsran/srsRAN_Project/tree/main/docker).

## License

### [AGPL v3 License](https://github.com/srsran/srsRAN_Project_helm/blob/main/LICENSE).
