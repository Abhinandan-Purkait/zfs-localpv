#!/usr/bin/env bash

# Write output to error output stream.
echo_stderr() {
  echo -e "${1}" >&2
}

die()
{
  local _return="${2:-1}"
  echo_stderr "$1"
  exit "${_return}"
}

help() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --branch <branch name>                    Name of the target branch.
  --tag <tag>                               Release tag.

Examples:
  $(basename "$0") --branch release/x.y
EOF
}

# yq-go eats up blank lines
# this function gets around that using diff with --ignore-blank-lines
yq_ibl()
{
  set +e
  diff_out=$(diff -B <(yq '.' "$2") <(yq "$1" "$2"))
  error=$?
  if [ "$error" != "0" ] && [ "$error" != "1" ]; then
    exit "$error"
  fi
  if [ -n "$diff_out" ]; then
    echo "$diff_out" | patch --quiet --no-backup-if-mismatch "$2" -
  fi
  set -euo pipefail
}

create_version_from_release_branch() {
  if [[ "$BRANCH_NAME" =~ ^(release/[0-9]+\.[0-9]+)$ ]]; then
    local EXTRACTED_VERSION=$(echo "$BRANCH_NAME" | grep -oP '(?<=release/)\d+\.\d+')
    CURRENT_CHART_VERSION=$(yq e '.version' "$CHART_YAML")
    if [[ "$CURRENT_CHART_VERSION" == *"-develop" ]]; then
      VERSION="${EXTRACTED_VERSION}.0-prerelease"
    elif [[ "$CURRENT_CHART_VERSION" == *"-prerelease" ]]; then
      VERSION=$CURRENT_CHART_VERSION
    else
      die "Current chart version doesn't match a develop or prerel format"
    fi
  else
    die "Invalid branch name format. Expected 'release/x.y' only"
  fi
}

create_version_from_tag() {
  if [[ "$TAG" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    local EXTRACTED_VERSION=$(echo "$TAG" | grep -oP '(?<=v)\d+\.\d+.\d+')
    if [[ $TYPE == "release" ]]; then
      VERSION="$(semver bump patch $EXTRACTED_VERSION)-prerelease"
      echo "release/$(echo $EXTRACTED_VERSION | cut -d'.' -f1,2)"
    elif [[ $TYPE == "develop" ]]; then
      VERSION="$(semver bump minor $EXTRACTED_VERSION)-develop"
      echo "develop"
    else
      die "Invalid type. Expected 'release' or 'develop'."
    fi
  else
    die "Invalid tag format. Expected 'vX.Y.Z'"
  fi
}

update_chart_yaml() {
  local VERSION=$1
  local APP_VERSION=$2

  yq_ibl ".version = \"$VERSION\" | .appVersion = \"$APP_VERSION\"" "$CHART_YAML"
  yq_ibl ".version = \"$VERSION\"" "$CRD_CHART_YAML"
  yq_ibl "(.dependencies[] | select(.name == \"crds\") | .version) = \"$VERSION\"" "$CHART_YAML"
  yq_ibl ".zfsPlugin.image.tag = \"$VERSION\"" "$VALUES_YAML"
}

set -euo pipefail

# Set the path to the Chart.yaml file
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-"$0"}")")"
ROOT_DIR="$SCRIPT_DIR/.."
CHART_DIR="$ROOT_DIR/deploy/helm/charts"
CHART_YAML="$CHART_DIR/Chart.yaml"
VALUES_YAML="$CHART_DIR/values.yaml"
CRD_CHART_NAME="crds"
CRD_CHART_YAML="$CHART_DIR/charts/$CRD_CHART_NAME/Chart.yaml"
# Final computed version to be set in this.
VERSION=""

# Parse arguments
while [ "$#" -gt 0 ]; do
  case $1 in
    -b|--branch)
      BRANCH_NAME=$2
      shift
      ;;
    -t|--tag)
      TAG=$2
      shift
      ;;
    --type)
      TYPE=$2
      shift
      ;;
    -h|--help)
      help
      exit 0
      ;;
    *)
      help
      die "Unknown option: $1"
      ;;
  esac
  shift
done

if [[ -n "${BRANCH_NAME-}" ]]; then
  create_version_from_release_branch
elif [[ -n "${TAG-}" && -n "${TYPE-}" ]]; then
  create_version_from_tag
else
  help
  die "Either --branch or --tag and --type must be specified."
fi

if [[ -n $VERSION ]]; then
  update_chart_yaml "$VERSION" "$VERSION"
else
  die "Failed to update the chart versions"
fi
