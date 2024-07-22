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
run_test "Test 1: Generate version from release branch name" \
         "1.2.0-prerelease" \
         --branch "release/1.2" --dry-run

run_test "Test 2: Invalid branch name" \
         "Invalid branch name format. Expected 'release/x.y' only" \
         --branch "feature/1.2" --dry-run

run_test "Test 3: Valid tag with type release [first release]" \
         "1.2.1-prerelease" \
         --tag "v1.2.0" --type "release" --dry-run

run_test "Test 4: Valid tag with type develop [first release]" \
         "1.3.0-develop" \
         --tag "v1.2.0" --type "develop" --dry-run

run_test "Test 5: Valid tag with type release [patch release]" \
         "1.2.3-prerelease" \
         --tag "v1.2.2" --type "release" --dry-run

run_test "Test 6: Valid tag with type develop [patch release]" \
         "1.3.0-develop" \
         --tag "v1.2.2" --type "develop" --dry-run

run_test "Test 7: Invalid tag format" \
         "Invalid tag format. Expected 'vX.Y.Z'" \
         --tag "1.2.3" --type "release" --dry-run

run_test "Test 8: Supply an rc tag, with release type" \
         "" \
         --tag "v1.2.3-rc" --type "release" --dry-run

run_test "Test 9: Supply an rc tag, with develop type" \
         "" \
         --tag "v1.2.3-rc" --type "develop" --dry-run