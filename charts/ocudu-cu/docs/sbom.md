<!--
SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
SPDX-License-Identifier: BSD-3-Clause-Open-MPI
-->

# OCUDU CU Helm profile SBOMs

Each production `ocudu-cu` chart release publishes three CycloneDX 1.6 SBOMs as
separate OCI attachments to the immutable chart manifest:

| Deployment profile | Filename | Included deployment images |
| --- | --- | --- |
| regular/default | `ocudu-cu-<version>.cdx.json` | CU |
| O1 | `ocudu-cu-<version>-o1.cdx.json` | CU, O1 adapter, NETCONF server |
| IPsec | `ocudu-cu-<version>-ipsec.cdx.json` | CU, IPsec sidecar |

The unqualified filename always represents the regular/default deployment. O1
and IPsec are independent profiles; an O1+IPsec combination is not supported.
The IPsec lint fixture selects the IPsec software set but is not a deployment
example.

These are deployment-profile Helm SBOMs. They identify the packaged chart, its
SHA-256, its OCI manifest digest, and every rendered image reference resolved
to an immutable OCI digest. They do not scan packages inside container images
and do not embed vulnerability results.

Merge-request preview artifacts and development-registry attachments are
unsigned. Production attachments contain embedded Ed25519 JSON Signature
Format signatures made by the protected release pipeline. Version `1.14.0`
predates this workflow and is not backfilled; signed attachments start with the
next normal chart release.

## Discover and download

Install ORAS 1.3.0, log in to `registry.gitlab.com` if the project is private,
and select the chart version:

```sh
repository=registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ocudu-cu
version=<version>
chart_digest=$(oras resolve "${repository}:${version}")

oras discover \
  --distribution-spec v1.1-referrers-tag \
  --artifact-type application/vnd.cyclonedx+json \
  "${repository}@${chart_digest}"
```

The discovery output lists one manifest digest per profile. Download a selected
attachment by its digest:

```sh
oras pull "${repository}@<attachment-manifest-digest>" --output sbom
```

GitLab does not provide the OCI Referrers API required by the default ORAS
discovery mode, so both CI and consumers must use the
`v1.1-referrers-tag` fallback shown above.

## Validate and verify

The repository provides a versioned tool image containing cdxgen 13.4.0 and
ORAS 1.3.0. Validate the expected profile with that image:

```sh
tool_image=registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/helm-sbom:13.4.0_1.0.1

docker run --rm --volume "$PWD:/workspace" --workdir /workspace \
  "$tool_image" .gitlab/ci/helm_sbom.sh validate \
  "sbom/ocudu-cu-<version>-o1.cdx.json" o1
docker run --rm --volume "$PWD:/workspace" --workdir /workspace \
  "$tool_image" cdx-verify \
  -i "sbom/ocudu-cu-<version>-o1.cdx.json" \
  --public-key <trusted-public-key.pem>
```

Use `default` or `ipsec` as the validator profile for the other filenames.
Obtain the trusted public key from the release owner.

## GitLab release setup

Create protected GitLab CI/CD variables named `HELM_SBOM_SIGN_PRIVATE_KEY`
and `HELM_SBOM_SIGN_PUBLIC_KEY`, both with type **File**. Their values must be
the matching PEM Ed25519 keys. Restrict them to the protected default branch
and do not expose them to merge-request pipelines.
