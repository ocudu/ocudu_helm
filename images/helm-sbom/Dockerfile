# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

FROM alpine/helm:3.16.2

ARG CDXGEN_VERSION=13.4.0
ARG ORAS_VERSION=1.3.0

RUN apk upgrade --no-cache && \
    apk add --no-cache coreutils curl jq libgcc libstdc++ openssl tar yq

RUN set -eux; \
    tmp_dir=$(mktemp -d); \
    for tool in cdxgen cdx-validate cdx-sign cdx-verify; do \
      asset="${tool}-linux-amd64-musl"; \
      release="https://github.com/cdxgen/cdxgen/releases/download/v${CDXGEN_VERSION}"; \
      curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        "${release}/${asset}" --output "${tmp_dir}/${asset}"; \
      curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        "${release}/${asset}.sha256" --output "${tmp_dir}/${asset}.sha256"; \
      published=$(awk 'NR == 1 { print $1 }' "${tmp_dir}/${asset}.sha256"); \
      printf '%s  %s\n' "${published}" "${tmp_dir}/${asset}" | sha256sum --check --status; \
      install -m 0755 "${tmp_dir}/${asset}" "/usr/local/bin/${tool}"; \
    done; \
    archive="oras_${ORAS_VERSION}_linux_amd64.tar.gz"; \
    release="https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}"; \
    curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
      "${release}/${archive}" --output "${tmp_dir}/${archive}"; \
    curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
      "${release}/oras_${ORAS_VERSION}_checksums.txt" --output "${tmp_dir}/oras-checksums.txt"; \
    published=$(awk -v name="${archive}" '$2 == name { print $1 }' "${tmp_dir}/oras-checksums.txt"); \
    printf '%s  %s\n' "${published}" "${tmp_dir}/${archive}" | sha256sum --check --status; \
    tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}" oras; \
    install -m 0755 "${tmp_dir}/oras" /usr/local/bin/oras; \
    rm -rf "${tmp_dir}"; \
    cdxgen --version; \
    cdx-validate --version; \
    cdx-sign --version; \
    cdx-verify --version; \
    oras version; \
    helm version --short

ENTRYPOINT []
