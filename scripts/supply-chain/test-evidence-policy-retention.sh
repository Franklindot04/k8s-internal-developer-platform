#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
VERSIONS_FILE="$ROOT/scripts/supply-chain/versions.env"
TMP_DIR="$ROOT/.tmp/supply-chain-policy-retention-test"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

version_value() {
  key="$1"
  value="$(awk -F= -v key="$key" '$1 == key { print $2 }' "$VERSIONS_FILE")"
  [ -n "$value" ] || fail "missing version key: $key"
  printf '%s\n' "${value#v}"
}

prepare_fixture() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  printf 'synthetic archive bytes\n' >"$TMP_DIR/supply-chain-fixture.tar"
  printf 'sha256:synthetic-local-image-id\n' >"$TMP_DIR/loaded-image-id.txt"
  cp "$ROOT/tests/fixtures/supply-chain-policy/critical.json" "$TMP_DIR/vulnerabilities.json"

  printf '%s\n' '{"bomFormat":"CycloneDX","specVersion":"1.6","metadata":{},"components":[]}' >"$TMP_DIR/sbom.cdx.json"
  printf '%s\n' '{"schema":{"version":"16.0.0"},"descriptor":{"name":"syft","version":"synthetic"},"artifacts":[],"source":{"type":"docker-archive","target":"supply-chain-fixture.tar"}}' >"$TMP_DIR/sbom.syft.json"
}

assert_policy_failure_retains_valid_evidence() {
  local status=0
  local syft_version=""
  local grype_version=""

  set +e
  ruby "$ROOT/scripts/supply-chain/evaluate-vulnerabilities.rb" \
    "$TMP_DIR/vulnerabilities.json" \
    "$TMP_DIR/policy-result.json"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "critical fixture should fail policy"
  ruby -rjson -e 'data = JSON.parse(File.read(ARGV.fetch(0))); abort unless data["decision"] == "FAIL"; abort unless data["blocking_finding_count"].positive?' "$TMP_DIR/policy-result.json"

  syft_version="$(version_value SYFT_VERSION)"
  grype_version="$(version_value GRYPE_VERSION)"
  ruby "$ROOT/scripts/supply-chain/validate-evidence.rb" generate \
    --evidence-dir "$TMP_DIR" \
    --archive "$TMP_DIR/supply-chain-fixture.tar" \
    --sbom "$TMP_DIR/sbom.cdx.json" \
    --scanner-sbom "$TMP_DIR/sbom.syft.json" \
    --vulnerabilities "$TMP_DIR/vulnerabilities.json" \
    --policy "$TMP_DIR/policy-result.json" \
    --versions-file "$VERSIONS_FILE" \
    --docker-image-id "$(cat "$TMP_DIR/loaded-image-id.txt")" \
    --syft-version "$syft_version" \
    --grype-version "$grype_version" \
    --target-architecture "linux/amd64" \
    --source-repository "synthetic-policy-retention-test" \
    --source-revision "synthetic-merge-sha"
  ruby "$ROOT/scripts/supply-chain/validate-evidence.rb" validate \
    --evidence-dir "$TMP_DIR" \
    --versions-file "$VERSIONS_FILE"
}

assert_malformed_policy_input_fails_closed() {
  local status=0

  printf '{' >"$TMP_DIR/malformed-vulnerabilities.json"
  set +e
  ruby "$ROOT/scripts/supply-chain/evaluate-vulnerabilities.rb" \
    "$TMP_DIR/malformed-vulnerabilities.json" \
    "$TMP_DIR/malformed-policy-result.json"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "malformed vulnerability input should fail"
  [ ! -f "$TMP_DIR/malformed-policy-result.json" ] || fail "malformed input must not produce retained policy evidence"
}

prepare_fixture
assert_policy_failure_retains_valid_evidence
assert_malformed_policy_input_fails_closed
printf '[ok] evidence policy-failure retention tests passed\n'
