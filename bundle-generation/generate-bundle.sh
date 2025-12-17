#!/usr/bin/env bash
#
# Generate RHCL Limitador Operator bundle variants using yq
#
# This script takes the upstream Limitador operator bundle and transforms it
# into RHCL bundles for dev, stage, and prod environments.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."
UPSTREAM_BUNDLE="${PROJECT_ROOT}/limitador-operator/bundle"
IMAGE_PULLSPECS="${PROJECT_ROOT}/image-pullspecs.yaml"
LIMITADOR_CONFIG="${SCRIPT_DIR}/limitador-operator.yaml"

# Check dependencies
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed"
    echo "Install: https://github.com/mikefarah/yq#install"
    exit 1
fi

# Verify config files exist
if [[ ! -f "$LIMITADOR_CONFIG" ]]; then
    echo "Error: Limitador config not found at $LIMITADOR_CONFIG"
    exit 1
fi

if [[ ! -f "$IMAGE_PULLSPECS" ]]; then
    echo "Error: Image pullspecs not found at $IMAGE_PULLSPECS"
    exit 1
fi

echo "========================================"
echo "Loading configuration from:"
echo "  Config:      $LIMITADOR_CONFIG"
echo "  Pullspecs:   $IMAGE_PULLSPECS"
echo "========================================"

# Read image pullspecs
OPERATOR_IMAGE=$(yq '.images.operator' "$IMAGE_PULLSPECS")
LIMITADOR_IMAGE=$(yq '.images.limitador' "$IMAGE_PULLSPECS")

echo ""
echo "Image pullspecs:"
echo "  operator:   $OPERATOR_IMAGE"
echo "  limitador:  $LIMITADOR_IMAGE"

# Extract SHAs from the quay.io images
OPERATOR_SHA="${OPERATOR_IMAGE##*@}"
LIMITADOR_SHA="${LIMITADOR_IMAGE##*@}"

# Read Limitador configuration values
CSV_NAME=$(yq '.csv.name' "$LIMITADOR_CONFIG")
CSV_VERSION=$(yq '.csv.version' "$LIMITADOR_CONFIG")
DISPLAY_NAME=$(yq '.csv.displayName' "$LIMITADOR_CONFIG")
DESCRIPTION=$(yq '.csv.description' "$LIMITADOR_CONFIG")
DOC_URL=$(yq '.links.documentation' "$LIMITADOR_CONFIG")
REPO_URL=$(yq '.links.repository' "$LIMITADOR_CONFIG")
VALID_SUBSCRIPTION=$(yq '.validSubscription' "$LIMITADOR_CONFIG")

# Check if icon is configured
ICON_BASE64=$(yq '.csv.icon[0].base64data // ""' "$LIMITADOR_CONFIG")
ICON_MEDIATYPE=$(yq '.csv.icon[0].mediatype // ""' "$LIMITADOR_CONFIG")

echo ""
echo "Limitador configuration:"
echo "  CSV name:     $CSV_NAME"
echo "  Version:      $CSV_VERSION"
echo "  Display name: $DISPLAY_NAME"

# Build registry mappings for each environment
get_operator_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$OPERATOR_IMAGE"
    else
        local registry=$(yq ".registries.${env}.operator" "$LIMITADOR_CONFIG")
        echo "${registry}@${OPERATOR_SHA}"
    fi
}

get_limitador_image() {
    local env=$1
    if [[ "$env" == "dev" ]]; then
        echo "$LIMITADOR_IMAGE"
    else
        local registry=$(yq ".registries.${env}.limitador" "$LIMITADOR_CONFIG")
        echo "${registry}@${LIMITADOR_SHA}"
    fi
}

# Generate bundle for each environment
for env in dev stage prod; do
    output_dir="${PROJECT_ROOT}/$(yq ".outputDirs.${env}" "$LIMITADOR_CONFIG")"
    manifests_dir="${output_dir}/manifests"
    metadata_dir="${output_dir}/metadata"

    echo ""
    echo "========================================"
    echo "Generating ${env} bundle"
    echo "Output: ${output_dir}"
    echo "========================================"

    # Clean and create output directories
    rm -rf "${output_dir}"
    mkdir -p "${manifests_dir}" "${metadata_dir}"

    # Copy all manifests from upstream
    cp "${UPSTREAM_BUNDLE}/manifests/"*.yaml "${manifests_dir}/"
    cp "${UPSTREAM_BUNDLE}/metadata/"*.yaml "${metadata_dir}/"

    CSV_FILE="${manifests_dir}/limitador-operator.clusterserviceversion.yaml"

    # Get the image references for this environment
    operator_image=$(get_operator_image "$env")
    limitador_image=$(get_limitador_image "$env")

    echo "  Operator:   ${operator_image}"
    echo "  Limitador:  ${limitador_image}"

    # Update CSV: operator container image
    yq -i '(.spec.install.spec.deployments[] | select(.name == "limitador-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .image) = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: containerImage annotation
    yq -i '.metadata.annotations.containerImage = "'"${operator_image}"'"' "${CSV_FILE}"

    # Update CSV: limitador in RELATED_IMAGE_LIMITADOR env var
    yq -i '(.spec.install.spec.deployments[] | select(.name == "limitador-operator-controller-manager") | .spec.template.spec.containers[] | select(.name == "manager") | .env[] | select(.name == "RELATED_IMAGE_LIMITADOR") | .value) = "'"${limitador_image}"'"' "${CSV_FILE}"

    # Update CSV: limitador in relatedImages
    yq -i '(.spec.relatedImages[] | select(.name == "limitador") | .image) = "'"${limitador_image}"'"' "${CSV_FILE}"

    # Update CSV: Add RHCL-specific feature annotations from config
    yq -i '.metadata.annotations["features.operators.openshift.io/disconnected"] = "'"$(yq '.features.disconnected' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/fips-compliant"] = "'"$(yq '.features.fips-compliant' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/proxy-aware"] = "'"$(yq '.features.proxy-aware' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/tls-profiles"] = "'"$(yq '.features.tls-profiles' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-aws"] = "'"$(yq '.features.token-auth-aws' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-azure"] = "'"$(yq '.features.token-auth-azure' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/token-auth-gcp"] = "'"$(yq '.features.token-auth-gcp' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/cnf"] = "'"$(yq '.features.cnf' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/cni"] = "'"$(yq '.features.cni' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.annotations["features.operators.openshift.io/csi"] = "'"$(yq '.features.csi' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"

    # Update CSV: valid subscription
    yq -i '.metadata.annotations["operators.openshift.io/valid-subscription"] = "[\"'"${VALID_SUBSCRIPTION}"'\"]"' "${CSV_FILE}"

    # Update CSV: Add architecture labels from config
    yq -i '.metadata.labels["operatorframework.io/os.linux"] = "'"$(yq '.architectures."os.linux"' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.amd64"] = "'"$(yq '.architectures.amd64' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"
    yq -i '.metadata.labels["operatorframework.io/arch.arm64"] = "'"$(yq '.architectures.arm64' "$LIMITADOR_CONFIG")"'"' "${CSV_FILE}"

    # Update CSV: Set display name and description
    yq -i ".spec.displayName = \"${DISPLAY_NAME}\"" "${CSV_FILE}"
    yq -i ".spec.description = \"${DESCRIPTION}\"" "${CSV_FILE}"

    # Update CSV: Set icon if configured
    if [[ -n "$ICON_BASE64" && -n "$ICON_MEDIATYPE" ]]; then
        yq -i ".spec.icon[0].base64data = \"${ICON_BASE64}\"" "${CSV_FILE}"
        yq -i ".spec.icon[0].mediatype = \"${ICON_MEDIATYPE}\"" "${CSV_FILE}"
    fi

    # Update CSV: Set documentation and repository links
    yq -i '.metadata.annotations.repository = "'"${REPO_URL}"'"' "${CSV_FILE}"

    # Update CSV: Remove replaces and skipRange (managed in catalog repo)
    yq -i 'del(.spec.replaces)' "${CSV_FILE}"
    yq -i 'del(.spec.skipRange)' "${CSV_FILE}"

    echo "  Done!"
done

echo ""
echo "========================================"
echo "All bundles generated successfully!"
echo "========================================"
echo ""
echo "Output directories:"
echo "  - bundle/       (production)"
echo "  - bundle-dev/   (development)"
echo "  - bundle-stage/ (staging)"
echo ""
