#!/usr/bin/env bash
set -euo pipefail

total_shards="${SWIFT_TEST_TOTAL_SHARDS:-}"
shard_index="${SWIFT_TEST_SHARD_INDEX:-}"

if [[ -z "$total_shards" || -z "$shard_index" ]]; then
  echo "SWIFT_TEST_TOTAL_SHARDS and SWIFT_TEST_SHARD_INDEX are required." >&2
  exit 2
fi

if ! [[ "$total_shards" =~ ^[1-9][0-9]*$ ]]; then
  echo "SWIFT_TEST_TOTAL_SHARDS must be a positive integer: ${total_shards}" >&2
  exit 2
fi

if ! [[ "$shard_index" =~ ^[0-9]+$ ]] || (( shard_index >= total_shards )); then
  echo "SWIFT_TEST_SHARD_INDEX must be in [0, ${total_shards}): ${shard_index}" >&2
  exit 2
fi

declare -a test_classes=()
while IFS= read -r test_class; do
  test_classes+=("$test_class")
done < <(
  swift test list \
    | awk -F'[./]' '/^[A-Za-z0-9_]+\.[A-Za-z0-9_]+\/[A-Za-z0-9_]+$/ { print $1 "." $2 }' \
    | sort -u
)

if (( ${#test_classes[@]} == 0 )); then
  echo "No XCTest test classes were discovered." >&2
  exit 1
fi

declare -a selected_classes=()
for test_class in "${test_classes[@]}"; do
  checksum="$(printf '%s' "$test_class" | cksum | awk '{print $1}')"
  if (( checksum % total_shards == shard_index )); then
    selected_classes+=("$test_class")
  fi
done

if (( ${#selected_classes[@]} == 0 )); then
  echo "No tests were assigned to shard ${shard_index}/${total_shards}." >&2
  exit 1
fi

declare -a escaped_classes=()
for test_class in "${selected_classes[@]}"; do
  escaped_classes+=("${test_class//./\\.}")
done

filter_body="$(printf '%s\n' "${escaped_classes[@]}" | paste -sd'|' -)"
filter_regex="^(${filter_body})/"

echo "Running shard $((shard_index + 1))/${total_shards} with ${#selected_classes[@]} test classes."
bash Scripts/swift_test.sh --filter "$filter_regex" "$@"
