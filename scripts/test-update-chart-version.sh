#!/usr/bin/env bash

# Path to the script to be tested
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-"$0"}")")"
SCRIPT_TO_TEST="$SCRIPT_DIR/update-chart-version.sh"

# Function to run a test case
run_test() {
  local test_name=$1
  local expected_output=$2
  shift 2
  local output

  echo "Running: $test_name"
  output=$("$SCRIPT_TO_TEST" "$@" 2>&1)
  if [ "$output" == "$expected_output" ]; then
    echo "PASS"
  else
    echo "FAIL"
    echo "Expected: $expected_output"
    echo "Got: $output"
  fi
  echo "----------------------------------------"
}

# Define test cases
run_test "Test 1: When commits are added and chart type is develop [branch creation]" \
         "1.2.0-prerelease" \
         --branch "release/1.2" --dry-run --chart-version "1.3.0-develop"

run_test "Test 2: When commits are added and chart type is prerelease [commit pushes]" \
         "" \
         --branch "release/1.2" --dry-run --chart-version "1.2.0-prerelease"

run_test "Test 3: Invalid branch name and chart type is prerelease" \
         "Invalid branch name format. Expected 'release/x.y' only" \
         --branch "feature/1.2" --dry-run --chart-version "1.2.0-prerelease"

run_test "Test 4: Invalid branch name and chart type is develop" \
         "Invalid branch name format. Expected 'release/x.y' only" \
         --branch "feature/1.2" --dry-run --chart-version "1.2.0-develop"

run_test "Test 5: Valid tag with type release and chart type is prerelease [first release] " \
         "1.2.1-prerelease" \
         --tag "v1.2.0" --type "release" --dry-run --chart-version "1.2.0-prerelease"

run_test "Test 6: Valid tag with type release and chart type is prerelease [patch release]" \
         "1.2.2-prerelease" \
         --tag "v1.2.1" --type "release" --dry-run --chart-version "1.2.1-prerelease"

run_test "Test 7: Invalid tag with workflow type release and chart type release" \
         "For prerelease, X.Y from current chart version (1.2) must exactly match X.Y from tag (1.4.0)" \
         --tag "v1.4.0" --type "release" --dry-run --chart-version "1.2.1-prerelease"

run_test "Test 8: Invalid tag with workflow type release and chart type develop" \
         "For develop, X.Y-1 from current chart version (1.2) must exactly match X.Y from tag (1.4.0)" \
         --tag "v1.4.0" --type "release" --dry-run --chart-version "1.2.1-develop"

run_test "Test 9: Valid tag with type develop and chart type is prerelease [first release]" \
         "1.3.0-develop" \
         --tag "v1.2.0" --type "develop" --dry-run --chart-version "1.2.0-prerelease"

run_test "Test 10: Valid tag with type develop and chart type is prerelease [patch release]" \
         "1.3.0-develop" \
         --tag "v1.2.1" --type "develop" --dry-run --chart-version "1.2.1-prerelease"

run_test "Test 11: Invalid tag with workflow type develop and chart type release " \
         "For prerelease, X.Y from current chart version (1.2) must exactly match X.Y from tag (1.4.0)" \
         --tag "v1.4.0" --type "develop" --dry-run --chart-version "1.2.1-prerelease"

run_test "Test 12: Invalid tag with workflow type develop and chart type develop" \
         "For develop, X.Y-1 from current chart version (1.2) must exactly match X.Y from tag (1.4.0)" \
         --tag "v1.4.0" --type "develop" --dry-run --chart-version "1.2.1-develop"

run_test "Test 13: rc tag, with type release and chart type prerelease" \
         "" \
         --tag "v1.2.3-rc" --type "release" --dry-run --chart-version "1.2.3-prerelease"

run_test "Test 14:rc tag, with type develop and chart type develop" \
         "" \
         --tag "v1.2.3-rc" --type "develop" --dry-run --chart-version "1.2.4-develop"
