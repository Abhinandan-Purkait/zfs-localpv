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
  --dry-run                                 Get the final version without modifying.
  --branch <branch name>                    Name of the target branch.
  --tag <tag>                               Release tag.
  --chart-version <version>                 Version of the current chart.

Examples:
  $(basename "$0") --branch release/x.y
EOF
}

check_tag_is_valid() {
    local tag="$1"
    local current_chart_version="$2"

    if [[ "$current_chart_version" == *"-prerelease" ]]; then
      allowed_diff=("" "patch" "prerelease")
      diff="$(semver diff "$tag" "$current_chart_version")"
      if ! [[ " ${allowed_diff[*]} " =~ " $diff " ]]; then
        die "For prerelease, X.Y from current chart version ($current_chart_version) must exactly match X.Y from tag ($tag)"
      fi
    elif [[ "$current_chart_version" == *"-develop" ]]; then
      compare="$(semver compare "$tag" "$current_chart_version")"
      if [[ "$compare" == "-1" ]]; then
        NO_OP=1
      fi
    fi
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

# RULES: This would run only when changes are pushed to a release/x.y branch.
# 1. Branch name can only be of format release/x.y
# 2. If current chart version of type develop(only possible on branch creation), 
#    then version generated is of format x.y.0-prerelease.
# 3. If current chart version of type prerelease(after branch creation and initial automated PR's merge), 
#    the workflow would be a no op, as it's already in a prerelease format.
create_version_from_release_branch() {
  if [[ "$BRANCH_NAME" =~ ^(release/[0-9]+\.[0-9]+)$ ]]; then
    local EXTRACTED_VERSION=$(echo "$BRANCH_NAME" | grep -oP '(?<=release/)\d+\.\d+')
    if [[ "$CURRENT_CHART_VERSION" == *"-develop" ]]; then
      VERSION="${EXTRACTED_VERSION}.0-prerelease"
    elif [[ "$CURRENT_CHART_VERSION" == *"-prerelease" ]]; then
      NO_OP=1
    else
      die "Current chart version doesn't match a develop or prerel format"
    fi
  else
    die "Invalid branch name format. Expected 'release/x.y' only"
  fi
}

# RULES: This would run only when tag is created.
# 1. Tag should be of format vX.Y.Z.
# 2. If tag is of format vX.Y.Z-rc, it would be a no op for the workflow.
# 3. The tag can only be vX.Y.Z if the current chart version is X.Y*-prerelease. Ex, v2.6.1 for v2.6.*-prerelease
# 4. The tag can only be vX.Y.Z if the current chart version is X.Y+1*-develop. Ex, v2.6.1 for v2.7.*-develop
# 5. For release branches if all the above holds then it bumps the patch version. Ex, v2.6.1 --> 2.6.2-prerelease
# 6. For develop branches if all the above holds then it bumps the minor version. Ex, v2.6.1 --> 2.7.0-develop
create_version_from_tag() {
  if [[ "$TAG" =~ ^(v[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    local EXTRACTED_VERSION=$(echo "$TAG" | grep -oP '(?<=v)\d+\.\d+.\d+')
    check_tag_is_valid "$EXTRACTED_VERSION" "$CURRENT_CHART_VERSION" 
    if [[ $TYPE == "release" ]]; then
      VERSION="$(semver bump patch $EXTRACTED_VERSION)-prerelease"
      if [[ -z $DRY_RUN ]];then
        echo "release/$(echo $EXTRACTED_VERSION | cut -d'.' -f1,2)"
      fi
    elif [[ $TYPE == "develop" ]]; then
      VERSION="$(semver bump minor $EXTRACTED_VERSION)-develop"
      if [[ -z $DRY_RUN ]];then
        echo "develop"
      fi
    else
      die "Invalid type. Expected 'release' or 'develop'."
    fi
  elif [[ "$TAG" == *"-rc" ]]; then
    NO_OP=1
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

DRY_RUN=
NO_OP=
CURRENT_CHART_VERSION=
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
    -d|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      help
      exit 0
      ;;
    -b|--branch)
      shift
      BRANCH_NAME=$1
      shift
      ;;
    -t|--tag)
      shift
      TAG=$1
      shift
      ;;
    --type)
      shift
      TYPE=$1
      shift
      ;;
    --chart-version)
      shift
      CURRENT_CHART_VERSION=$1
      shift
      ;;
    *)
      help
      die "Unknown option: $1"
      ;;
  esac
done

if [[ -z $CURRENT_CHART_VERSION ]]; then
  CURRENT_CHART_VERSION=$(yq e '.version' "$CHART_YAML")
fi

if [[ -n "${BRANCH_NAME-}" ]]; then
  create_version_from_release_branch
elif [[ -n "${TAG-}" && -n "${TYPE-}" ]]; then
  create_version_from_tag
else
  help
  die "Either --branch or --tag and --type must be specified."
fi

if [[ -z $NO_OP ]]; then
  if [[ -n $VERSION ]]; then
    if [[ -z $DRY_RUN ]];then
      update_chart_yaml "$VERSION" "$VERSION"
    else
      echo "$VERSION"
    fi
  else
    die "Failed to update the chart versions"
  fi
fi
