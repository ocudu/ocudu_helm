#!/bin/sh

# SPDX-FileCopyrightText: Copyright (C) 2021-2026 Software Radio Systems Limited
# SPDX-License-Identifier: BSD-3-Clause-Open-MPI

set -eu

CDXGEN_VERSION="13.4.0"
CYCLONEDX_SPEC_VERSION="1.6"
SUPPLIER="Software Radio Systems Limited"

usage() {
  cat >&2 <<EOF
Usage:
  $0 generate CHART_PATH OUTPUT_DIRECTORY [CHART_OCI_MANIFEST_DIGEST]
  $0 add-chart-digest OUTPUT_DIRECTORY CHART_OCI_REFERENCE CHART_OCI_MANIFEST_DIGEST
  $0 validate SBOM_FILE PROFILE

PROFILE is one of: default, o1, ipsec.
EOF
  exit 2
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required tool not found: $1" >&2
    exit 1
  }
}

property_value() {
  file=$1
  property=$2
  jq -r --arg property "$property" \
    '.metadata.component.properties[]? | select(.name == $property) | .value' "$file"
}

expected_repositories() {
  case "$1" in
    default)
      echo "registry.gitlab.com/ocudu/ocudu/images/cu"
      ;;
    o1)
      cat <<EOF
registry.gitlab.com/ocudu/ocudu/images/cu
registry.gitlab.com/ocudu/ocudu_elements/ocudu_oran_apps/ocudu_netconf/netconf_nightly_amd64
registry.gitlab.com/ocudu/ocudu_elements/ocudu_oran_apps/ocudu_o1_adapter/o1_adapter_nightly_amd64
EOF
      ;;
    ipsec)
      cat <<EOF
registry.gitlab.com/ocudu/ocudu/images/cu
registry.gitlab.com/ocudu/ocudu_elements/ocudu_helm/ipsec-sidecar
EOF
      ;;
    *) usage ;;
  esac
}

validate_bom() {
  bom=$1
  profile=$2

  require_tool jq
  require_tool cdx-validate

  cdx-validate --strict --fail-severity critical --no-include-manual \
    --report json --report-file /dev/null -i "$bom"
  jq -e \
    --arg spec "$CYCLONEDX_SPEC_VERSION" \
    --arg supplier "$SUPPLIER" \
    --arg profile "$profile" '
      .bomFormat == "CycloneDX" and
      .specVersion == $spec and
      (.vulnerabilities | not) and
      .metadata.supplier.name == $supplier and
      any(.metadata.authors[]?; .name == $supplier) and
      .metadata.component.supplier.name == $supplier and
      .metadata.component.author == $supplier and
      (.metadata.component.purl | startswith("pkg:helm/ocudu-cu@")) and
      (.metadata.component.hashes | length == 1) and
      .metadata.component.hashes[0].alg == "SHA-256" and
      (.metadata.component.hashes[0].content | test("^[0-9a-f]{64}$")) and
      any(.metadata.component.properties[]?;
        .name == "ocudu:deployment-profile" and .value == $profile) and
      all(.components[]? | select(.type == "container");
        any(.properties[]?;
          .name == "ocudu:oci-manifest-digest" and
          (.value | test("^sha256:[0-9a-f]{64}$"))))
    ' "$bom" >/dev/null

  actual=$(mktemp)
  expected=$(mktemp)
  jq -r '
    .components[]? |
    select(.type == "container") |
    .properties[]? |
    select(.name == "ocudu:oci-repository") |
    .value
  ' "$bom" | sort -u > "$actual"
  expected_repositories "$profile" | sort -u > "$expected"
  if ! diff -u "$expected" "$actual"; then
    rm -f "$actual" "$expected"
    echo "ERROR: unexpected container component set for ${profile}" >&2
    exit 1
  fi
  rm -f "$actual" "$expected"

  root_ref=$(jq -r '.metadata.component["bom-ref"]' "$bom")
  jq -e --arg root "$root_ref" '
    ([.components[]? | select(.type == "container") | .["bom-ref"]] | sort) as $images |
    ([.dependencies[]? | select(.ref == $root) | .dependsOn[]?] |
      map(select(. as $ref | $images | index($ref))) | sort) == $images
  ' "$bom" >/dev/null

  echo "Validated ${bom} (${profile})"
}

generate_boms() {
  chart_path=$1
  output_dir=$2
  chart_manifest_digest=${3:-}

  for tool in helm yq jq sha256sum cdxgen cdx-validate oras; do
    require_tool "$tool"
  done

  chart_path=$(cd "$chart_path" && pwd)
  chart_name=$(yq eval -r '.name' "${chart_path}/Chart.yaml")
  chart_version=$(yq eval -r '.version' "${chart_path}/Chart.yaml")
  if [ "$chart_name" != "ocudu-cu" ]; then
    echo "ERROR: profile definitions currently exist only for ocudu-cu" >&2
    exit 1
  fi
  if [ -n "$chart_manifest_digest" ] && ! printf '%s\n' "$chart_manifest_digest" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
    echo "ERROR: invalid chart OCI manifest digest: ${chart_manifest_digest}" >&2
    exit 1
  fi

  mkdir -p "$output_dir"
  output_dir=$(cd "$output_dir" && pwd)
  work_dir=$(mktemp -d)
  trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
  package_dir="${work_dir}/package"
  mkdir -p "$package_dir"

  if [ -n "${SBOM_CHART_PACKAGE_FILE:-}" ]; then
    package_file=$(cd "$(dirname "$SBOM_CHART_PACKAGE_FILE")" && pwd)/$(basename "$SBOM_CHART_PACKAGE_FILE")
    [ -f "$package_file" ] || {
      echo "ERROR: SBOM_CHART_PACKAGE_FILE does not exist: ${package_file}" >&2
      exit 1
    }
    expected_package="${chart_name}-${chart_version}.tgz"
    if [ "$(basename "$package_file")" != "$expected_package" ]; then
      echo "ERROR: expected package name ${expected_package}, got $(basename "$package_file")" >&2
      exit 1
    fi
  else
    if grep -q '^dependencies:' "${chart_path}/Chart.yaml"; then
      helm dependency update "$chart_path"
    fi
    helm package "$chart_path" --destination "$package_dir" >/dev/null
    package_file="${package_dir}/${chart_name}-${chart_version}.tgz"
  fi
  [ -f "$package_file" ] || {
    echo "ERROR: expected package was not created: ${package_file}" >&2
    exit 1
  }
  chart_sha256=$(sha256sum "$package_file" | awk '{ print $1 }')
  tar -xzf "$package_file" -C "$work_dir"
  packaged_chart="${work_dir}/${chart_name}"

  base_bom="${work_dir}/base.cdx.json"
  cdxgen \
    --type helm \
    --spec-version "$CYCLONEDX_SPEC_VERSION" \
    --project-name "$chart_name" \
    --project-version "$chart_version" \
    --no-recurse \
    --no-install-deps \
    --quiet \
    --output "$base_bom" \
    "$packaged_chart"

  generated_at=${SBOM_GENERATED_AT:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
  root_ref="pkg:helm/${chart_name}@${chart_version}"

  for profile in default o1 ipsec; do
    rendered="${work_dir}/${profile}.yaml"
    case "$profile" in
      default)
        helm template sbom "$packaged_chart" > "$rendered"
        suffix=""
        ;;
      o1)
        helm template sbom "$packaged_chart" \
          --values "${packaged_chart}/values-o1.yaml" > "$rendered"
        suffix="-o1"
        ;;
      ipsec)
        # The lint fixture selects the supported IPsec software set. It is not
        # represented as a deployable values example in the SBOM.
        helm template sbom "$packaged_chart" \
          --values "${packaged_chart}/ci/lint-values-ipsec.yaml" > "$rendered"
        suffix="-ipsec"
        ;;
    esac

    images="${work_dir}/${profile}-images.txt"
    yq eval-all -r '
      select(.kind == "Deployment") |
      .spec.template.spec.initContainers[]?.image,
      .spec.template.spec.containers[]?.image
    ' "$rendered" | sed '/^null$/d; /^$/d' | sort -u > "$images"
    [ -s "$images" ] || {
      echo "ERROR: no container images found for ${profile}" >&2
      exit 1
    }

    image_components="${work_dir}/${profile}-components.jsonl"
    : > "$image_components"
    while IFS= read -r image; do
      digest=$(oras resolve "$image")
      if ! printf '%s\n' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
        echo "ERROR: failed to resolve an immutable digest for ${image}: ${digest}" >&2
        exit 1
      fi

      last_segment=${image##*/}
      case "$last_segment" in
        *:*)
          tag=${last_segment##*:}
          repository=${image%:*}
          ;;
        *)
          tag=latest
          repository=$image
          ;;
      esac
      component_name=${repository##*/}
      component_group=${repository%/*}
      digest_hex=${digest#sha256:}
      bom_ref="urn:ocudu:oci:${repository}@${digest}"
      encoded_name=$(jq -nr --arg value "$component_name" '$value | @uri')
      encoded_repository=$(jq -nr --arg value "$repository" '$value | @uri')
      encoded_tag=$(jq -nr --arg value "$tag" '$value | @uri')
      purl="pkg:oci/${encoded_name}@${digest}?repository_url=${encoded_repository}&tag=${encoded_tag}"

      jq -cn \
        --arg ref "$bom_ref" \
        --arg group "$component_group" \
        --arg name "$component_name" \
        --arg tag "$tag" \
        --arg purl "$purl" \
        --arg image "$image" \
        --arg repository "$repository" \
        --arg digest "$digest" \
        --arg digestHex "$digest_hex" '
          {
            type: "container",
            "bom-ref": $ref,
            group: $group,
            name: $name,
            version: $tag,
            purl: $purl,
            hashes: [{alg: "SHA-256", content: $digestHex}],
            properties: [
              {name: "ocudu:oci-reference", value: $image},
              {name: "ocudu:oci-repository", value: $repository},
              {name: "ocudu:oci-manifest-digest", value: $digest}
            ],
            externalReferences: [{type: "distribution", url: ("oci://" + $repository + "@" + $digest)}]
          }
        ' >> "$image_components"
    done < "$images"

    output="${output_dir}/${chart_name}-${chart_version}${suffix}.cdx.json"
    serial_hash=$(printf '%s\n' "${root_ref}:${profile}:${chart_sha256}" | sha256sum | awk '{ print $1 }')
    serial_number=$(jq -nr --arg hash "$serial_hash" '
      "urn:uuid:" +
      $hash[0:8] + "-" +
      $hash[8:12] + "-" +
      "8" + $hash[13:16] + "-" +
      "8" + $hash[17:20] + "-" +
      $hash[20:32]
    ')
    jq -s \
      --arg spec "$CYCLONEDX_SPEC_VERSION" \
      --arg supplier "$SUPPLIER" \
      --arg generatedAt "$generated_at" \
      --arg generatorVersion "$CDXGEN_VERSION" \
      --arg chartName "$chart_name" \
      --arg chartVersion "$chart_version" \
      --arg chartSha "$chart_sha256" \
      --arg chartDigest "$chart_manifest_digest" \
      --arg profile "$profile" \
      --arg serialNumber "$serial_number" \
      --arg rootRef "$root_ref" '
        .[0] as $base |
        (.[1:] | map(select(type == "object"))) as $images |
        ($base.metadata.component["bom-ref"] // $rootRef) as $oldRoot |
        (($base.components // []) |
          map(select(.["bom-ref"] != $oldRoot and .purl != $rootRef))) as $chartComponents |
        (($base.dependencies // []) |
          map(select(.ref == $oldRoot)) | first | .dependsOn // []) as $chartDependencies |
        ([
          {name: "ocudu:deployment-profile", value: $profile},
          {name: "ocudu:packaged-chart-sha256", value: $chartSha},
          {name: "ocudu:generator", value: ("cdxgen " + $generatorVersion)},
          {name: "ocudu:generated-at", value: $generatedAt}
        ] + if $chartDigest == "" then [] else
          [{name: "ocudu:chart-oci-manifest-digest", value: $chartDigest}]
        end) as $rootProperties |
        {
          bomFormat: "CycloneDX",
          specVersion: $spec,
          serialNumber: $serialNumber,
          version: 1,
          metadata: {
            timestamp: $generatedAt,
            tools: {
              components: [{
                type: "application",
                author: "OWASP Foundation",
                name: "cdxgen",
                version: $generatorVersion
              }]
            },
            authors: [{name: $supplier}],
            supplier: {name: $supplier},
            component: {
              type: "application",
              "bom-ref": $rootRef,
              supplier: {name: $supplier},
              author: $supplier,
              name: $chartName,
              version: $chartVersion,
              purl: $rootRef,
              hashes: [{alg: "SHA-256", content: $chartSha}],
              properties: $rootProperties
            }
          },
          components: ($chartComponents + $images | unique_by(.["bom-ref"])),
          dependencies: (
            (($base.dependencies // []) |
              map(select(.ref != $oldRoot))) +
            [{
              ref: $rootRef,
              dependsOn: (($chartDependencies + ($images | map(.["bom-ref"]))) | unique)
            }] +
            ($images | map({ref: .["bom-ref"], dependsOn: []}))
            | unique_by(.ref)
          )
        }
      ' "$base_bom" "$image_components" > "$output"

    validate_bom "$output" "$profile"
  done

  echo "Generated profile SBOMs in ${output_dir}"
}

add_chart_digest() {
  output_dir=$1
  chart_reference=$2
  chart_digest=$3

  require_tool jq
  require_tool cdx-validate
  if ! printf '%s\n' "$chart_digest" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
    echo "ERROR: invalid chart OCI manifest digest: ${chart_digest}" >&2
    exit 1
  fi

  found=false
  for bom in "$output_dir"/*.cdx.json; do
    [ -f "$bom" ] || continue
    found=true
    tmp_bom=$(mktemp)
    jq \
      --arg reference "$chart_reference" \
      --arg digest "$chart_digest" '
        .metadata.component.properties = (
          [.metadata.component.properties[]? |
            select(.name != "ocudu:chart-oci-reference" and
                   .name != "ocudu:chart-oci-manifest-digest")] +
          [
            {name: "ocudu:chart-oci-reference", value: $reference},
            {name: "ocudu:chart-oci-manifest-digest", value: $digest}
          ]
        ) |
        .metadata.component.externalReferences = (
          [.metadata.component.externalReferences[]? |
            select(.type != "distribution" or
                   (.url | startswith("oci://") | not))] +
          [{type: "distribution", url: ("oci://" + $reference + "@" + $digest)}]
        )
      ' "$bom" > "$tmp_bom"
    mv "$tmp_bom" "$bom"
    profile=$(property_value "$bom" "ocudu:deployment-profile")
    validate_bom "$bom" "$profile"
  done
  if [ "$found" != true ]; then
    echo "ERROR: no SBOM files found in ${output_dir}" >&2
    exit 1
  fi
}

[ "$#" -ge 1 ] || usage
command=$1
shift
case "$command" in
  generate)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
    generate_boms "$@"
    ;;
  add-chart-digest)
    [ "$#" -eq 3 ] || usage
    add_chart_digest "$@"
    ;;
  validate)
    [ "$#" -eq 2 ] || usage
    validate_bom "$@"
    ;;
  *) usage ;;
esac
