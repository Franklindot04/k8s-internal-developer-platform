#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
EVIDENCE_DIR="${SUPPLY_CHAIN_EVIDENCE_DIR:-$ROOT/.tmp/supply-chain-evidence}"
TOOLS_DIR="${SUPPLY_CHAIN_TOOLS_DIR:-$ROOT/.tmp/supply-chain-tools}"
VERSIONS_FILE="$ROOT/scripts/supply-chain/versions.env"
FIXTURE_DIR="$ROOT/tests/fixtures/supply-chain-fixture"
ARCHIVE="$EVIDENCE_DIR/supply-chain-fixture.tar"
SBOM="$EVIDENCE_DIR/sbom.cdx.json"
SCANNER_SBOM="$EVIDENCE_DIR/sbom.syft.json"
VULNERABILITIES="$EVIDENCE_DIR/vulnerabilities.json"
POLICY_RESULT="$EVIDENCE_DIR/policy-result.json"
IMAGE_TAG="idp/supply-chain-fixture:test"
PLATFORM="linux/amd64"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

require_tool() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || fail "required tool missing: $tool"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{ print $1 }'
  else
    fail "required checksum tool missing: sha256sum or shasum"
  fi
}

sanitize_json_file() {
  local file="$1"

  SUPPLY_CHAIN_REPO_ROOT="$ROOT" ruby -rjson -e '
    root = ENV.fetch("SUPPLY_CHAIN_REPO_ROOT")
    home = ENV.fetch("HOME", "")
    scrub = lambda do |value|
      case value
      when Hash
        value.transform_values { |child| scrub.call(child) }
      when Array
        value.map { |child| scrub.call(child) }
      when String
        value.gsub(root, "<redacted-local-path>").gsub(home, "<redacted-local-path>")
      else
        value
      end
    end
    path = ARGV.fetch(0)
    data = JSON.parse(File.read(path))
    File.write(path, "#{JSON.generate(scrub.call(data))}\n")
  ' "$file"
}

require_docker() {
  require_tool docker
  docker info >/dev/null 2>&1 || fail "Docker is required and must be running for supply-chain evidence"
}

tool_path() {
  printf '%s/bin/%s\n' "$TOOLS_DIR" "$1"
}

tool_version() {
  local bin="$1"
  "$bin" version | awk -F': *' '$1 == "Version" { print $2; found = 1; exit } END { if (!found) exit 1 }'
}

prepare_output() {
  rm -rf "$EVIDENCE_DIR"
  mkdir -p "$EVIDENCE_DIR"
}

install_tools() {
  bash "$ROOT/scripts/supply-chain/install-evidence-tools.sh" install
}

source_test() {
  require_docker
  bash "$ROOT/scripts/supply-chain/fixture.sh" test
}

build_archive() {
  require_docker
  mkdir -p "$EVIDENCE_DIR"
  rm -f "$ARCHIVE"
  docker buildx build \
    --platform "$PLATFORM" \
    --provenance=false \
    --sbom=false \
    --target runtime \
    --tag "$IMAGE_TAG" \
    --output "type=docker,dest=$ARCHIVE" \
    "$FIXTURE_DIR"
  [ -s "$ARCHIVE" ] || fail "image archive was not created"
  sha256_file "$ARCHIVE" >"$EVIDENCE_DIR/artifact-sha256.txt"
  printf '[ok] archive SHA-256: %s\n' "$(cat "$EVIDENCE_DIR/artifact-sha256.txt")"
}

load_archive() {
  require_docker
  [ -f "$ARCHIVE" ] || fail "image archive missing"
  archive_sha="$(sha256_file "$ARCHIVE")"
  docker load --input "$ARCHIVE" >"$EVIDENCE_DIR/docker-load.txt"
  image_id="$(docker image inspect "$IMAGE_TAG" --format '{{.Id}}')"
  [ -n "$image_id" ] || fail "loaded image ID missing"
  printf '%s\n' "$image_id" >"$EVIDENCE_DIR/loaded-image-id.txt"
  printf '%s\n' "$archive_sha" >"$EVIDENCE_DIR/runtime-source-archive-sha256.txt"
  printf '[ok] loaded Docker image ID: %s\n' "$image_id"
}

smoke_loaded_image() {
  [ -f "$EVIDENCE_DIR/loaded-image-id.txt" ] || fail "loaded image ID record missing"
  bash "$ROOT/scripts/supply-chain/fixture.sh" smoke-image "$IMAGE_TAG"
}

generate_sbom() {
  syft_bin="$(tool_path syft)"
  [ -x "$syft_bin" ] || fail "Syft is not installed"
  (
    cd "$EVIDENCE_DIR"
    "$syft_bin" "docker-archive:$(basename "$ARCHIVE")" \
      -o "cyclonedx-json=$(basename "$SBOM")" \
      -o "syft-json=$(basename "$SCANNER_SBOM")"
  )
  sanitize_json_file "$SBOM"
  sanitize_json_file "$SCANNER_SBOM"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    abort("[error] SBOM is not CycloneDX JSON") unless data["bomFormat"] == "CycloneDX"
    abort("[error] SBOM specVersion missing") unless data["specVersion"].to_s != ""
    abort("[error] SBOM components missing") unless data.key?("components") && data["components"].is_a?(Array)
    abort("[error] SBOM metadata missing") unless data["metadata"].is_a?(Hash)
  ' "$SBOM"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    abort("[error] Syft JSON schema missing") unless data["schema"].is_a?(Hash)
    abort("[error] Syft JSON descriptor missing") unless data["descriptor"].is_a?(Hash)
    abort("[error] Syft JSON artifacts missing") unless data["artifacts"].is_a?(Array)
    abort("[error] Syft JSON source missing") unless data["source"].is_a?(Hash)
  ' "$SCANNER_SBOM"
  sha256_file "$SBOM" >"$EVIDENCE_DIR/sbom-sha256.txt"
  sha256_file "$SCANNER_SBOM" >"$EVIDENCE_DIR/sbom-syft-sha256.txt"
  printf '[ok] SBOM SHA-256: %s\n' "$(cat "$EVIDENCE_DIR/sbom-sha256.txt")"
  printf '[ok] scanner SBOM SHA-256: %s\n' "$(cat "$EVIDENCE_DIR/sbom-syft-sha256.txt")"
}

scan_vulnerabilities() {
  grype_bin="$(tool_path grype)"
  [ -x "$grype_bin" ] || fail "Grype is not installed"
  if ! (
    cd "$EVIDENCE_DIR"
    "$grype_bin" "docker-archive:$(basename "$ARCHIVE")" -o json >"$(basename "$VULNERABILITIES")"
  ); then
    fail "Grype scan failed; infrastructure/tooling failure"
  fi
  sanitize_json_file "$VULNERABILITIES"
  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    abort("[error] vulnerability report matches missing") unless data["matches"].is_a?(Array)
  ' "$VULNERABILITIES"
  sha256_file "$VULNERABILITIES" >"$EVIDENCE_DIR/vulnerabilities-sha256.txt"
  printf '[ok] vulnerability report SHA-256: %s\n' "$(cat "$EVIDENCE_DIR/vulnerabilities-sha256.txt")"
}

evaluate_policy() {
  ruby "$ROOT/scripts/supply-chain/evaluate-vulnerabilities.rb" "$VULNERABILITIES" "$POLICY_RESULT"
}

generate_manifest() {
  syft_bin="$(tool_path syft)"
  grype_bin="$(tool_path grype)"
  syft_version="$(tool_version "$syft_bin")"
  grype_version="$(tool_version "$grype_bin")"
  source_repository="${SOURCE_REPOSITORY:-$(basename "$ROOT")}"
  source_revision="${SOURCE_REVISION:-$(git rev-parse HEAD)}"
  ruby "$ROOT/scripts/supply-chain/validate-evidence.rb" generate \
    --evidence-dir "$EVIDENCE_DIR" \
    --archive "$ARCHIVE" \
    --sbom "$SBOM" \
    --scanner-sbom "$SCANNER_SBOM" \
    --vulnerabilities "$VULNERABILITIES" \
    --policy "$POLICY_RESULT" \
    --versions-file "$VERSIONS_FILE" \
    --docker-image-id "$(cat "$EVIDENCE_DIR/loaded-image-id.txt")" \
    --syft-version "$syft_version" \
    --grype-version "$grype_version" \
    --target-architecture "$PLATFORM" \
    --source-repository "$source_repository" \
    --source-revision "$source_revision"
}

verify_evidence() {
  ruby "$ROOT/scripts/supply-chain/validate-evidence.rb" validate \
    --evidence-dir "$EVIDENCE_DIR" \
    --versions-file "$VERSIONS_FILE"
}

all() {
  prepare_output
  install_tools
  source_test
  build_archive
  load_archive
  smoke_loaded_image
  generate_sbom
  scan_vulnerabilities
  evaluate_policy
  generate_manifest
  verify_evidence
}

case "${1:-all}" in
  install-tools) install_tools ;;
  test) source_test ;;
  build) build_archive ;;
  load) load_archive ;;
  smoke) smoke_loaded_image ;;
  sbom) generate_sbom ;;
  scan) scan_vulnerabilities ;;
  policy) evaluate_policy ;;
  manifest) generate_manifest ;;
  verify) verify_evidence ;;
  all) all ;;
  *) fail "usage: $0 {install-tools|test|build|load|smoke|sbom|scan|policy|manifest|verify|all}" ;;
esac
