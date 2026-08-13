#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VALIDATOR="$ROOT/scripts/validate-generated-structure.sh"
PYTHON_BIN="${PYTHON:-python3}"
PYTHONPATH="$ROOT/tools/platformctl/src"
MARKER="# Generated from ../service.yaml by the platform self-service generator.
# Do not edit directly; update the PlatformService specification instead."

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

make_repo() {
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/services/minimal-api"
  cp "$ROOT/tools/platformctl/tests/fixtures/values/minimal-single/services/minimal-api/service.yaml" "$tmp/services/minimal-api/service.yaml"
  printf '%s\n' "$tmp"
}

run_validator() {
  "$VALIDATOR" "$1" >/dev/null 2>&1
}

assert_pass() {
  name="$1"
  repo="$2"
  output="$("$VALIDATOR" "$repo" 2>&1)" || {
    printf '%s\n' "$output" >&2
    fail "$name: expected generated structure validation to pass"
  }
}

assert_fail() {
  name="$1"
  repo="$2"
  if run_validator "$repo"; then
    fail "$name: expected generated structure validation to fail"
  fi
}

write_owned() {
  path="$1"
  {
    printf '%s\n' "$MARKER"
    printf 'kind: test\n'
  } >"$path"
}

with_repo() {
  repo="$(make_repo)"
  "$@" "$repo"
  rm -rf "$repo"
}

source_only_passes() {
  assert_pass "source-only service" "$1"
}

owned_pair_passes() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_pass "canonical owned generated pair" "$repo"
}

only_values_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  assert_fail "partial pair with only values.yaml" "$repo"
}

only_application_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "partial pair with only application.yaml" "$repo"
}

unexpected_entry_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  touch "$repo/services/minimal-api/generated/metadata.yaml"
  assert_fail "unexpected generated entry" "$repo"
}

missing_source_fails() {
  repo="$1"
  rm "$repo/services/minimal-api/service.yaml"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "generated pair without source" "$repo"
}

symlink_generated_dir_fails() {
  repo="$1"
  mkdir -p "$repo/elsewhere"
  ln -s "$repo/elsewhere" "$repo/services/minimal-api/generated"
  assert_fail "symlinked generated directory" "$repo"
}

symlink_values_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  touch "$repo/target"
  ln -s "$repo/target" "$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "symlinked values artifact" "$repo"
}

symlink_application_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  touch "$repo/target"
  ln -s "$repo/target" "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "symlinked application artifact" "$repo"
}

nonregular_artifact_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "non-regular generated artifact" "$repo"
}

unowned_values_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  printf 'hand-written\n' >"$repo/services/minimal-api/generated/values.yaml"
  write_owned "$repo/services/minimal-api/generated/application.yaml"
  assert_fail "unowned values artifact" "$repo"
}

unowned_application_fails() {
  repo="$1"
  mkdir -p "$repo/services/minimal-api/generated"
  write_owned "$repo/services/minimal-api/generated/values.yaml"
  printf 'hand-written\n' >"$repo/services/minimal-api/generated/application.yaml"
  assert_fail "unowned application artifact" "$repo"
}

real_generator_output_passes() {
  repo="$1"
  (
    cd "$repo"
    PYTHONPATH="$PYTHONPATH" "$PYTHON_BIN" -m platformctl service generate services/minimal-api/service.yaml >/dev/null
  )
  [ "$(find "$repo/services/minimal-api/generated" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = "2" ] ||
    fail "real generator output did not create exactly two files"
  assert_pass "real generator output" "$repo"
}

structure_accepts_owned_drift_verify_rejects() {
  repo="$1"
  (
    cd "$repo"
    PYTHONPATH="$PYTHONPATH" "$PYTHON_BIN" -m platformctl service generate services/minimal-api/service.yaml >/dev/null
  )
  {
    printf '%s\n' "$MARKER"
    printf 'fullnameOverride: drifted\n'
  } >"$repo/services/minimal-api/generated/values.yaml"
  assert_pass "owned drift remains structurally valid" "$repo"
  if (
    cd "$repo"
    PYTHONPATH="$PYTHONPATH" "$PYTHON_BIN" -m platformctl service verify services/minimal-api/service.yaml >/dev/null 2>&1
  ); then
    fail "verify should reject owned content drift"
  fi
}

with_repo source_only_passes
with_repo owned_pair_passes
with_repo only_values_fails
with_repo only_application_fails
with_repo unexpected_entry_fails
with_repo missing_source_fails
with_repo symlink_generated_dir_fails
with_repo symlink_values_fails
with_repo symlink_application_fails
with_repo nonregular_artifact_fails
with_repo unowned_values_fails
with_repo unowned_application_fails
with_repo real_generator_output_passes
with_repo structure_accepts_owned_drift_verify_rejects

printf '[ok] generated structure validator tests passed\n'
