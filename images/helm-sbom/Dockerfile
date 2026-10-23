# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

FROM alpine:3.24.3 AS downloader

ARG CDXGEN_VERSION=13.4.0

RUN apk add --no-cache coreutils curl

RUN set -eux; \
    tmp_dir=$(mktemp -d); \
    mkdir /out; \
    for tool in cdxgen cdx-validate cdx-sign cdx-verify; do \
      asset="${tool}-linux-amd64-musl"; \
      release="https://github.com/cdxgen/cdxgen/releases/download/v${CDXGEN_VERSION}"; \
      curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        "${release}/${asset}" --output "${tmp_dir}/${asset}"; \
      curl --fail --location --silent --show-error --retry 5 --retry-all-errors \
        "${release}/${asset}.sha256" --output "${tmp_dir}/${asset}.sha256"; \
      published=$(awk 'NR == 1 { print $1 }' "${tmp_dir}/${asset}.sha256"); \
      printf '%s  %s\n' "${published}" "${tmp_dir}/${asset}" | sha256sum --check --status; \
      install -m 0755 "${tmp_dir}/${asset}" "/out/${tool}"; \
    done; \
    rm -rf "${tmp_dir}"

FROM alpine:3.24.3

RUN apk add --no-cache \
      ca-certificates \
      coreutils \
      helm \
      jq \
      libgcc \
      libstdc++ \
      openssl \
      oras-cli \
      tar \
      yq-go

COPY --from=downloader /out/ /usr/local/bin/

RUN set -eux; \
    cdxgen --version; \
    cdx-validate --version; \
    cdx-sign --version; \
    cdx-verify --version; \
    oras version; \
    helm version --short; \
    yq --version

ENTRYPOINT []
