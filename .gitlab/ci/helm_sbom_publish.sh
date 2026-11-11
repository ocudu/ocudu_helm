#!/bin/sh

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -eu

MEDIA_TYPE="application/vnd.cyclonedx+json"
PIPELINE_ANNOTATION="ocudu.io/sbom-ci-pipeline-id"
CREATED_ANNOTATION="ocudu.io/sbom-created-at"

usage() {
  echo "Usage: $0 development|production CHART_PATH OUTPUT_DIRECTORY" >&2
  exit 2
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required tool not found: $1" >&2
    exit 1
  }
}

[ "$#" -eq 3 ] || usage
release_mode=$1
chart_path=$2
output_dir=$3
case "$release_mode" in
  development|production) ;;
  *) usage ;;
esac

for variable in CI_REGISTRY CI_REGISTRY_USER CI_JOB_TOKEN CI_PROJECT_PATH CI_PIPELINE_ID; do
  eval "value=\${${variable}:-}"
  if [ -z "$value" ]; then
    echo "ERROR: required CI variable is empty: ${variable}" >&2
    exit 1
  fi
done
for tool in helm yq jq oras cdxgen cdx-validate cdx-sign cdx-verify openssl; do
  require_tool "$tool"
done

chart_path=$(cd "$chart_path" && pwd)
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)
chart_name=$(yq eval -r '.name' "${chart_path}/Chart.yaml")
base_version=$(yq eval -r '.version' "${chart_path}/Chart.yaml")
case "$release_mode" in
  development)
    version="${base_version}-dev.${CI_PIPELINE_ID}"
    sign_boms=false
    ;;
  production)
    version=$base_version
    sign_boms=true
    ;;
esac

repository="${CI_REGISTRY}/${CI_PROJECT_PATH}/${chart_name}"
chart_reference="${repository}:${version}"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
release_chart="${work_dir}/${chart_name}"
package_file="${work_dir}/${chart_name}-${version}.tgz"
existing=false

if oras resolve "$chart_reference" >/dev/null 2>&1; then
  existing=true
  echo "Chart ${chart_reference} already exists; checking whether this is a retry"
  helm pull "oci://${repository}" --version "$version" --destination "$work_dir"
  tar -xzf "$package_file" -C "$work_dir"
  owner_pipeline=$(yq eval -r ".annotations.\"${PIPELINE_ANNOTATION}\" // \"\"" "${release_chart}/Chart.yaml")
  if [ "$owner_pipeline" != "$CI_PIPELINE_ID" ]; then
    # A merge without a version bump only adds to "## Unreleased": never
    # overwrite the release that is already in the registry.
    if [ "$release_mode" = production ]; then
      echo "Version ${version} is already published, nothing to release"
      exit 0
    fi
    echo "ERROR: chart ${chart_reference} already exists and belongs to another pipeline" >&2
    echo "Refusing to overwrite or attach SBOMs to an unrelated chart version" >&2
    exit 1
  fi
  generated_at=$(yq eval -r ".annotations.\"${CREATED_ANNOTATION}\"" "${release_chart}/Chart.yaml")
else
  cp -R "$chart_path" "$release_chart"
  generated_at=${CI_PIPELINE_CREATED_AT:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
  RELEASE_VERSION=$version CI_PIPELINE_MARKER=$CI_PIPELINE_ID SBOM_CREATED_AT=$generated_at \
    yq eval '
      .version = strenv(RELEASE_VERSION) |
      .annotations."ocudu.io/sbom-ci-pipeline-id" = strenv(CI_PIPELINE_MARKER) |
      .annotations."ocudu.io/sbom-created-at" = strenv(SBOM_CREATED_AT)
    ' -i "${release_chart}/Chart.yaml"
  if grep -q '^dependencies:' "${release_chart}/Chart.yaml"; then
    helm dependency update "$release_chart"
  fi
  helm package "$release_chart" --destination "$work_dir" >/dev/null
fi

if [ "$sign_boms" = true ]; then
  if [ -z "${HELM_SBOM_SIGN_PRIVATE_KEY:-}" ] || [ ! -f "$HELM_SBOM_SIGN_PRIVATE_KEY" ]; then
    echo "ERROR: HELM_SBOM_SIGN_PRIVATE_KEY must be a protected GitLab File variable" >&2
    exit 1
  fi
  if [ -z "${HELM_SBOM_SIGN_PUBLIC_KEY:-}" ] || [ ! -f "$HELM_SBOM_SIGN_PUBLIC_KEY" ]; then
    echo "ERROR: HELM_SBOM_SIGN_PUBLIC_KEY must be a protected GitLab File variable" >&2
    exit 1
  fi
  derived_public="${work_dir}/derived-public.pem"
  expected_public="${work_dir}/expected-public.pem"
  openssl pkey -in "$HELM_SBOM_SIGN_PRIVATE_KEY" -pubout -outform DER -out "$derived_public"
  openssl pkey -pubin -in "$HELM_SBOM_SIGN_PUBLIC_KEY" -outform DER -out "$expected_public"
  if ! cmp -s "$derived_public" "$expected_public"; then
    echo "ERROR: HELM_SBOM_SIGN_PRIVATE_KEY does not match HELM_SBOM_SIGN_PUBLIC_KEY" >&2
    exit 1
  fi
fi

SBOM_CHART_PACKAGE_FILE=$package_file SBOM_GENERATED_AT=$generated_at \
  .gitlab/ci/helm_sbom.sh generate "$release_chart" "$output_dir"

if [ "$existing" = false ]; then
  echo "Publishing immutable chart ${chart_reference}"
  helm push "$package_file" "oci://${CI_REGISTRY}/${CI_PROJECT_PATH}"
else
  echo "Chart upload already completed by this pipeline; resuming SBOM publication"
fi

chart_digest=$(oras resolve "$chart_reference")
if ! printf '%s\n' "$chart_digest" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
  echo "ERROR: unable to resolve immutable chart digest for ${chart_reference}" >&2
  exit 1
fi
.gitlab/ci/helm_sbom.sh add-chart-digest "$output_dir" "$chart_reference" "$chart_digest"

if [ "$sign_boms" = true ]; then
  for bom in "$output_dir"/*.cdx.json; do
    cdx-sign -i "$bom" -k "$HELM_SBOM_SIGN_PRIVATE_KEY" \
      --algorithm Ed25519 --key-id ocudu-helm-sbom-2026
    cdx-verify -i "$bom" --public-key "$HELM_SBOM_SIGN_PUBLIC_KEY"
  done
else
  echo "Development SBOMs remain unsigned"
fi

attachment_digests="${work_dir}/attachment-digests.txt"
: > "$attachment_digests"
subject="${repository}@${chart_digest}"
discovery="${work_dir}/discovery.json"
oras discover \
  --distribution-spec v1.1-referrers-tag \
  --artifact-type "$MEDIA_TYPE" \
  --format json "$subject" > "$discovery"
for bom in "$output_dir"/*.cdx.json; do
  filename=$(basename "$bom")
  profile=$(jq -r '.metadata.component.properties[] | select(.name == "ocudu:deployment-profile") | .value' "$bom")
  attachment_digest=$(jq -r --arg profile "$profile" '
    [.referrers[]? |
      select(.annotations."org.ocudu.helm.deployment-profile" == $profile) |
      .digest] | last // ""
  ' "$discovery")
  if [ -n "$attachment_digest" ]; then
    existing_dir=$(mktemp -d "${work_dir}/existing.XXXXXX")
    oras pull "${repository}@${attachment_digest}" --output "$existing_dir"
    if ! cmp -s "$bom" "${existing_dir}/${filename}"; then
      echo "ERROR: ${profile} attachment already exists with different content" >&2
      exit 1
    fi
    echo "Reusing existing ${profile} attachment ${attachment_digest}"
  else
    attach_result=$(cd "$output_dir" && oras attach \
      --distribution-spec v1.1-referrers-tag \
      --artifact-type "$MEDIA_TYPE" \
      --annotation "org.opencontainers.image.created=${generated_at}" \
      --annotation "org.ocudu.helm.deployment-profile=${profile}" \
      --format json \
      "$subject" "${filename}:${MEDIA_TYPE}")
    attachment_digest=$(printf '%s\n' "$attach_result" | jq -r '.digest')
  fi
  if ! printf '%s\n' "$attachment_digest" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
    echo "ERROR: invalid attachment digest for ${filename}" >&2
    exit 1
  fi
  printf '%s\t%s\n' "$attachment_digest" "$filename" >> "$attachment_digests"

  pull_dir=$(mktemp -d "${work_dir}/pull.XXXXXX")
  oras pull "${repository}@${attachment_digest}" --output "$pull_dir"
  pulled_bom="${pull_dir}/${filename}"
  cmp "$bom" "$pulled_bom"
  .gitlab/ci/helm_sbom.sh validate "$pulled_bom" "$profile"
  if [ "$sign_boms" = true ]; then
    cdx-verify -i "$pulled_bom" --public-key "$HELM_SBOM_SIGN_PUBLIC_KEY"
  fi
done

oras discover \
  --distribution-spec v1.1-referrers-tag \
  --artifact-type "$MEDIA_TYPE" \
  --format json "$subject" > "$discovery"
while IFS="$(printf '\t')" read -r attachment_digest filename; do
  if ! jq -e --arg digest "$attachment_digest" \
    'any(.referrers[]?; .digest == $digest)' "$discovery" >/dev/null; then
    echo "ERROR: published attachment was not discoverable: ${filename}" >&2
    exit 1
  fi
done < "$attachment_digests"

cp "$package_file" "$output_dir/"
echo "Published and verified the SBOM attachments for ${chart_reference}@${chart_digest}"
