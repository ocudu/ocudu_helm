# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

ARG STRONGSWAN_VERSION=6.0.4
FROM ubuntu:26.04 AS runtime
ARG STRONGSWAN_VERSION

COPY strongswan.d/ /etc/strongswan.d/
COPY scripts/ /usr/local/bin/

# charon-systemd pulls in strongswan-swanctl, which brings the vici interface. The
# strongswan metapackage, strongswan-starter and strongswan-charon are deliberately absent:
# they configure a second daemon, and two daemons sharing one network namespace would
# compete for the same UDP ports, policies, states and routes.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        charon-systemd \
        strongswan-swanctl \
        strongswan-pki \
        libstrongswan-extra-plugins \
        iproute2 \
        catatonit && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    chmod +x /usr/local/bin/*.sh && \
    STRONGSWAN_VERSION="${STRONGSWAN_VERSION}" /usr/local/bin/check-runtime-support.sh

# Extra tooling for network validation. Kept in a separate stage so none of it can reach a
# deployed workload: the tools that prove a tunnel carries traffic are also the tools for
# reading traffic off the wire, and they have no place next to a live key.
FROM runtime AS poc

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        lksctp-tools \
        socat \
        tcpdump \
        iputils-ping \
        iperf3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
