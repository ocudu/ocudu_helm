<!--
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
-->

# OCUDU Kubernetes Helm Charts

[![License: BSD 3-Clause Open MPI](https://img.shields.io/badge/License-BSD%203--Clause%20Open%20MPI-blue.svg)](LICENSE)

Kubernetes Helm charts for deploying OCUDU 5G Radio Access Network (RAN) components and supporting infrastructure.

## Available Charts

For the current version of each chart, see its `Chart.yaml` or `CHANGELOG.md`.

### RAN Charts

| Chart | Description |
|-------|-------------|
| [ocudu-gnb](charts/ocudu-gnb/) | 5G gNB — CU and DU combined in a single pod |
| [ocudu-cu](charts/ocudu-cu/) | 5G CU (Central Unit) — N2, N3, F1-C, F1-U |
| [ocudu-du](charts/ocudu-du/) | 5G DU (Distributed Unit) — F1-C, F1-U |
| [ocudu-cu-cp](charts/ocudu-cu-cp/) | 5G CU-CP (Central Unit, Control Plane) — N2, E1, F1-C |
| [ocudu-cu-up](charts/ocudu-cu-up/) | 5G CU-UP (Central Unit, User Plane) — N3, E1, F1-U |

### Infrastructure Charts

| Chart | Description |
|-------|-------------|
| [linuxptp](charts/linuxptp/) | PTP time synchronization (ptp4l, phc2sys, ts2phc) |
| [grafana-ocudu](charts/grafana-ocudu/) | Monitoring stack (Grafana + InfluxDB3 + Telegraf) |
| [influxdb3](charts/influxdb3/) | InfluxDB3 time-series database |
| [onap-smo-lite](charts/onap-smo-lite/) | ONAP SMO components for O1 management |
| [rt-tests](charts/rt-tests/) | Real-time performance testing tools |
| [ru_emulator](charts/ru_emulator/) | Radio Unit (O-RU) emulator for testing |
| [tuned](charts/tuned/) | System tuning profiles for low-latency |

## Which chart do I need?

The RAN charts deploy the same gNB split up different ways. Pick **one** of these shapes:

- **`ocudu-gnb`** — CU and DU in a single pod. The simplest deployment; start here unless
  you have a reason to split.
- **`ocudu-cu` + `ocudu-du`** — CU and DU as separate pods (for example, DU at a cell site
  and CU centralised), connected over F1.
- **`ocudu-cu-cp` + `ocudu-cu-up` + `ocudu-du`** — the CU is further split into a control
  plane (CU-CP) and a user plane (CU-UP), connected over E1, with the DU over F1. The most
  granular shape.

All five RAN charts share the same feature set (IPsec, O1, NetworkPolicy, persistence, and
more). For which chart supports what, and how to configure each feature, see the
[documentation](docs/README.md).

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

## Documentation

- [Documentation index and feature matrix](docs/README.md) — shared guides for every RAN
  feature (IPsec, O1, security, operations, storage, networking, SR-IOV, hugepages), plus
  a table of which chart supports what.
- Each chart's own README covers that chart specifically:
  - [ocudu-gnb](charts/ocudu-gnb/README.md)
  - [ocudu-cu-cp](charts/ocudu-cu-cp/README.md)
  - [ocudu-cu-up](charts/ocudu-cu-up/README.md)
  - [linuxptp](charts/linuxptp/README.md)
  - [grafana-ocudu](charts/grafana-ocudu/README.md)
  - [influxdb3](charts/influxdb3/README.md)
  - [onap-smo-lite](charts/onap-smo-lite/README.md)
  - [rt-tests](charts/rt-tests/README.md)
  - [ru_emulator](charts/ru_emulator/README.md)
  - [tuned](charts/tuned/README.md)

The RAN charts also publish signed, deployment-profile
[CycloneDX SBOMs](HELM_SBOM.md) alongside production OCI chart releases.

## Container Images

Container images are available in the GitLab Container Registry:
- **Chart images**: https://gitlab.com/ocudu/ocudu_elements/ocudu_helm/container_registry
- **Split 7.2 images** (ru_emulator & ocudu-gnb): https://gitlab.com/ocudu/ocudu/container_registry

## License

This project is licensed under the BSD 3-Clause Open MPI variant License – see the LICENSE file for details.
Portions of this software may implement 3GPP specifications, which may be subject to additional licensing requirements.
