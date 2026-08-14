#!/usr/bin/env bash
set -Eeuo pipefail

readonly REGISTRY_HOST="ghcr.io"
readonly SOURCE_REPOSITORY="Franklindot04/k8s-internal-developer-platform"
readonly CANDIDATE_REPOSITORY="ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates"
readonly AUTHORITATIVE_REPOSITORY="ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture"
readonly TARGET_PLATFORM="linux/amd64"
readonly CANDIDATE_PACKAGE_NAME="k8s-internal-developer-platform%2Fsupply-chain-fixture-candidates"
readonly AUTHORITATIVE_PACKAGE_NAME="k8s-internal-developer-platform%2Fsupply-chain-fixture"
readonly MAX_EVIDENCE_BYTES=10485760

ROOT=""
WORK_DIR=""
RESULT_FILE=""
DOCKER_AUTH_DIR=""
TOOLS_DIR=""
PUBLICATION_STATUS="failure"
PUBLICATION_MODE="unknown"
EVIDENCE_UPLOAD_ALLOWED="false"
LOGIN_ATTEMPTED="false"

fail() {
  printf '[error] %s\n' "$1" >&2
  exit 1
}

log() {
  printf '[ok] %s\n' "$1"
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool missing: $1"
}

sha256_file() {
  sha256sum "$1" | awk '{ print $1 }'
}

validate_digest() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'SupplyChainPublication.validate_digest!(ARGV.fetch(0))' "$1"
}

validate_source_revision() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'SupplyChainPublication.validate_source_revision!(ARGV.fetch(0))' "$1"
}

candidate_tag() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'puts SupplyChainPublication.candidate_tag(ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2))' "$1" "$2" "$3"
}

authoritative_tag() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'puts SupplyChainPublication.authoritative_tag(ARGV.fetch(0))' "$1"
}

write_result() {
  mkdir -p "$(dirname "$RESULT_FILE")"
  {
    printf 'status=%s\n' "$PUBLICATION_STATUS"
    printf 'mode=%s\n' "$PUBLICATION_MODE"
    printf 'scope=true\n'
    printf 'evidence_upload_allowed=%s\n' "$EVIDENCE_UPLOAD_ALLOWED"
    printf 'artifact_name=%s\n' "${ARTIFACT_NAME:-}"
    printf 'source_revision=%s\n' "${SOURCE_REVISION:-}"
    printf 'candidate_repository=%s\n' "$CANDIDATE_REPOSITORY"
    printf 'candidate_tag=%s\n' "${CANDIDATE_TAG:-}"
    printf 'candidate_digest=%s\n' "${CANDIDATE_REGISTRY_DIGEST:-}"
    printf 'candidate_visibility=%s\n' "${CANDIDATE_VISIBILITY:-}"
    printf 'policy_decision=%s\n' "${POLICY_DECISION:-}"
    printf 'authoritative_repository=%s\n' "$AUTHORITATIVE_REPOSITORY"
    printf 'authoritative_tag=%s\n' "${AUTHORITATIVE_TAG:-}"
    printf 'authoritative_digest=%s\n' "${AUTHORITATIVE_TAG_DIGEST:-}"
    printf 'authoritative_visibility=%s\n' "${AUTHORITATIVE_VISIBILITY:-}"
  } >"$RESULT_FILE"
}

cleanup() {
  set +e
  write_result
  if [ "$LOGIN_ATTEMPTED" = "true" ]; then
    docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true
  fi
  if [ -n "${DOCKER_AUTH_DIR:-}" ]; then
    rm -rf "$DOCKER_AUTH_DIR"
  fi
}

retry() {
  local attempts="$1"
  shift
  local delay=2
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    sleep "$delay"
    n=$((n + 1))
  done
}

imagetools_manifest_json() {
  local reference="$1"
  docker buildx imagetools inspect "$reference" --format '{{json .Manifest}}'
}

inspect_registry_reference() {
  local reference="$1"
  local output="$2"
  local error_file="$3"

  if imagetools_manifest_json "$reference" >"$output" 2>"$error_file"; then
    return 0
  fi

  if grep -Eiq '(not found|manifest unknown|404)' "$error_file"; then
    return 4
  fi

  return 1
}

manifest_digest() {
  jq -r '.digest // empty' "$1"
}

manifest_media_type() {
  jq -r '.mediaType // empty' "$1"
}

verify_package_metadata() {
  local encoded_package="$1"
  local expected_visibility="$2"
  local role="$3"
  local output="$WORK_DIR/${role}-package.json"

  GH_TOKEN="${GITHUB_TOKEN:?}" retry 10 gh api "/users/Franklindot04/packages/container/$encoded_package" >"$output"

  local visibility=""
  visibility="$(jq -r '.visibility // empty' "$output")"
  if [ "$visibility" != "$expected_visibility" ]; then
    fail "$role package visibility is $visibility, expected $expected_visibility"
  fi

  local linked_repo=""
  linked_repo="$(jq -r '.repository.full_name // empty' "$output")"
  if [ "$linked_repo" != "$SOURCE_REPOSITORY" ]; then
    fail "$role package repository linkage is missing or incorrect"
  fi

  case "$role" in
    candidate) CANDIDATE_VISIBILITY="$visibility" ;;
    authoritative) AUTHORITATIVE_VISIBILITY="$visibility" ;;
    *) fail "unknown package role: $role" ;;
  esac
}

install_evidence_tools() {
  SUPPLY_CHAIN_TOOLS_DIR="$TOOLS_DIR" bash scripts/supply-chain/install-evidence-tools.sh install
  export PATH="$TOOLS_DIR/bin:$PATH"
}

write_runtime_proof() {
  local image_ref="$1"
  local output="$WORK_DIR/runtime-proof.json"

  bash scripts/supply-chain/fixture.sh smoke-image "$image_ref"
  printf '{"health":"PASS","runtime_user":"65532:65532","graceful_shutdown":"PASS","exit_code":0}\n' >"$output"
}

generate_sbom_and_vulnerability() {
  local archive="$1"

  syft "docker-archive:$(basename "$archive")" -o cyclonedx-json="$WORK_DIR/sbom.cdx.json" -o syft-json="$WORK_DIR/sbom.syft.json"
  grype "docker-archive:$(basename "$archive")" -o json >"$WORK_DIR/vulnerabilities.json"

  set +e
  ruby scripts/supply-chain/evaluate-vulnerabilities.rb "$WORK_DIR/vulnerabilities.json" "$WORK_DIR/policy-result.json"
  local policy_exit="$?"
  set -e

  POLICY_DECISION="$(jq -r '.decision // empty' "$WORK_DIR/policy-result.json")"
  [ "$POLICY_DECISION" = "PASS" ] || [ "$POLICY_DECISION" = "FAIL" ] || fail "vulnerability policy did not produce a valid decision"
  [ "$policy_exit" -eq 0 ] || [ "$POLICY_DECISION" = "FAIL" ] || fail "vulnerability policy evaluator failed"
}

verify_artifact_size() {
  local file="$1"
  local size=""
  size="$(wc -c <"$file" | tr -d ' ')"
  [ "$size" -le "$MAX_EVIDENCE_BYTES" ] || fail "evidence file too large: $(basename "$file")"
}

build_publication_evidence() {
  local status="$1"
  local authoritative_digest="${2:-}"
  local evidence_path="$WORK_DIR/publication-evidence.json"
  local handoff_path="$WORK_DIR/image-reference.json"

  PUBLICATION_STATUS="$status" \
    AUTHORITATIVE_TAG_DIGEST="$authoritative_digest" \
    CYCLONEDX_PATH="$WORK_DIR/sbom.cdx.json" \
    SYFT_JSON_PATH="$WORK_DIR/sbom.syft.json" \
    VULNERABILITY_PATH="$WORK_DIR/vulnerabilities.json" \
    POLICY_RESULT_PATH="$WORK_DIR/policy-result.json" \
    PUBLICATION_EVIDENCE_PATH="$evidence_path" \
    HANDOFF_PATH="$handoff_path" \
    ruby -r ./scripts/supply-chain/publication.rb -e '
    input = {
      source_revision: ENV.fetch("SOURCE_REVISION"),
      workflow_run_id: ENV.fetch("WORKFLOW_RUN_ID"),
      workflow_run_attempt: ENV.fetch("WORKFLOW_RUN_ATTEMPT"),
      status: ENV.fetch("PUBLICATION_STATUS"),
      candidate_repository: SupplyChainPublication::CANDIDATE_REPOSITORY,
      authoritative_repository: SupplyChainPublication::AUTHORITATIVE_REPOSITORY,
      build_metadata_digest: ENV.fetch("BUILD_METADATA_DIGEST"),
      candidate_digest: ENV.fetch("CANDIDATE_REGISTRY_DIGEST"),
      scan_target_digest: ENV.fetch("VERIFIED_SCAN_TARGET_DIGEST"),
      authoritative_digest: ENV["AUTHORITATIVE_TAG_DIGEST"],
      syft_version: ENV.fetch("SYFT_VERSION_ACTUAL"),
      grype_version: ENV.fetch("GRYPE_VERSION_ACTUAL"),
      cyclonedx_filename: "sbom.cdx.json",
      cyclonedx_sha256: SupplyChainPublication.sha256_file(ENV.fetch("CYCLONEDX_PATH")),
      syft_json_filename: "sbom.syft.json",
      syft_json_sha256: SupplyChainPublication.sha256_file(ENV.fetch("SYFT_JSON_PATH")),
      vulnerability_report_filename: "vulnerabilities.json",
      vulnerability_report_sha256: SupplyChainPublication.sha256_file(ENV.fetch("VULNERABILITY_PATH")),
      vulnerability_database: ENV.fetch("VULNERABILITY_DATABASE"),
      policy_result_filename: "policy-result.json",
      policy_result_sha256: SupplyChainPublication.sha256_file(ENV.fetch("POLICY_RESULT_PATH")),
      policy_decision: ENV.fetch("POLICY_DECISION")
    }
    input.delete(:authoritative_repository) unless %w[published existing].include?(input.fetch(:status))
    input.delete(:authoritative_digest) unless %w[published existing].include?(input.fetch(:status))
    manifest = SupplyChainPublication.build_manifest(input, versions_file: "scripts/supply-chain/versions.env")
    SupplyChainPublication.write_manifest(ENV.fetch("PUBLICATION_EVIDENCE_PATH"), manifest)
    if %w[published existing].include?(input.fetch(:status))
      handoff = SupplyChainPublication.build_handoff(manifest, SupplyChainPublication.sha256_file(ENV.fetch("PUBLICATION_EVIDENCE_PATH")))
      File.write(ENV.fetch("HANDOFF_PATH"), JSON.pretty_generate(handoff) + "\n")
      SupplyChainPublication.validate_handoff_object!(handoff, manifest)
    end
  '

  ruby scripts/supply-chain/validate-publication.rb validate-publication --publication "$evidence_path"
  if [ "$status" = "published" ] || [ "$status" = "existing" ]; then
    ruby scripts/supply-chain/validate-publication.rb validate-handoff --publication "$evidence_path" --handoff "$handoff_path"
  fi
}

prepare_success_artifact() {
  local stage="$WORK_DIR/artifact"
  mkdir -p "$stage"
  cp "$WORK_DIR/publication-evidence.json" "$stage/"
  cp "$WORK_DIR/publication-evidence.json.sha256" "$stage/"
  cp "$WORK_DIR/image-reference.json" "$stage/"
  cp "$WORK_DIR/sbom.cdx.json" "$stage/"
  cp "$WORK_DIR/sbom.syft.json" "$stage/"
  cp "$WORK_DIR/vulnerabilities.json" "$stage/"
  cp "$WORK_DIR/policy-result.json" "$stage/"
  cp "$WORK_DIR/runtime-proof.json" "$stage/"
  cp "$WORK_DIR/build-metadata.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/candidate-manifest.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/authoritative-manifest.json" "$stage/" 2>/dev/null || true
  find "$stage" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
    verify_artifact_size "$file"
  done
  EVIDENCE_UPLOAD_ALLOWED="true"
}

prepare_failure_artifact() {
  local stage="$WORK_DIR/artifact"
  mkdir -p "$stage"
  cp "$WORK_DIR/publication-evidence.json" "$stage/"
  cp "$WORK_DIR/publication-evidence.json.sha256" "$stage/"
  cp "$WORK_DIR/sbom.cdx.json" "$stage/"
  cp "$WORK_DIR/sbom.syft.json" "$stage/"
  cp "$WORK_DIR/vulnerabilities.json" "$stage/"
  cp "$WORK_DIR/policy-result.json" "$stage/"
  cp "$WORK_DIR/runtime-proof.json" "$stage/"
  find "$stage" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
    verify_artifact_size "$file"
  done
  EVIDENCE_UPLOAD_ALLOWED="true"
}

pull_and_verify_exact_digest() {
  local digest_ref="$1"
  local expected_digest="$2"
  local repo_digest_match=""

  docker pull "$digest_ref"
  repo_digest_match="$(docker image inspect "$digest_ref" --format '{{join .RepoDigests "\n"}}' | grep -Fx "$digest_ref" || true)"
  [ "$repo_digest_match" = "$digest_ref" ] || fail "pulled image RepoDigests did not include expected digest reference"
  VERIFIED_SCAN_TARGET_DIGEST="$expected_digest"
}

scan_runtime_and_policy() {
  local digest_ref="$1"
  local archive="$WORK_DIR/supply-chain-fixture.tar"

  pull_and_verify_exact_digest "$digest_ref" "${2:?}"
  write_runtime_proof "$digest_ref"
  docker image save --output "$archive" "$digest_ref"
  ARCHIVE_SHA256="$(sha256_file "$archive")"
  (cd "$WORK_DIR" && generate_sbom_and_vulnerability "$archive")
}

publish_first() {
  PUBLICATION_MODE="first"
  CANDIDATE_TAG="$(candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT")"
  local candidate_ref="$CANDIDATE_REPOSITORY:$CANDIDATE_TAG"
  local candidate_digest_ref=""

  docker buildx build \
    --platform "$TARGET_PLATFORM" \
    --provenance=false \
    --sbom=false \
    --push \
    --tag "$candidate_ref" \
    --metadata-file "$WORK_DIR/build-metadata.json" \
    tests/fixtures/supply-chain-fixture

  BUILD_METADATA_DIGEST="$(jq -r '."containerimage.digest" // empty' "$WORK_DIR/build-metadata.json")"
  validate_digest "$BUILD_METADATA_DIGEST"

  retry 10 inspect_registry_reference "$candidate_ref" "$WORK_DIR/candidate-manifest.json" "$WORK_DIR/candidate-inspect.err" || fail "candidate registry inspection failed"
  CANDIDATE_REGISTRY_DIGEST="$(manifest_digest "$WORK_DIR/candidate-manifest.json")"
  CANDIDATE_MEDIA_TYPE="$(manifest_media_type "$WORK_DIR/candidate-manifest.json")"
  validate_digest "$CANDIDATE_REGISTRY_DIGEST"
  [ -n "$CANDIDATE_MEDIA_TYPE" ] || fail "candidate manifest media type missing"
  [ "$BUILD_METADATA_DIGEST" = "$CANDIDATE_REGISTRY_DIGEST" ] || fail "build metadata digest and candidate registry digest mismatch"

  verify_package_metadata "$CANDIDATE_PACKAGE_NAME" "private" "candidate"

  candidate_digest_ref="$CANDIDATE_REPOSITORY@$CANDIDATE_REGISTRY_DIGEST"
  scan_runtime_and_policy "$candidate_digest_ref" "$CANDIDATE_REGISTRY_DIGEST"

  SYFT_VERSION_ACTUAL="$(syft version -o json | jq -r '.version')"
  GRYPE_VERSION_ACTUAL="$(grype version -o json | jq -r '.version')"
  VULNERABILITY_DATABASE="$(grype db status -o json | jq -r '.built // .updated // .schemaVersion // "unknown"')"

  if [ "$POLICY_DECISION" = "FAIL" ]; then
    BUILD_METADATA_DIGEST="$CANDIDATE_REGISTRY_DIGEST"
    build_publication_evidence "blocked"
    prepare_failure_artifact
    fail "vulnerability policy blocked authoritative publication"
  fi
  [ "$POLICY_DECISION" = "PASS" ] || fail "vulnerability policy did not pass"

  docker buildx imagetools create \
    --prefer-index=false \
    --metadata-file "$WORK_DIR/promotion-metadata.json" \
    --tag "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" \
    "$candidate_digest_ref"

  retry 10 inspect_registry_reference "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" "$WORK_DIR/authoritative-manifest.json" "$WORK_DIR/authoritative-inspect.err" || fail "authoritative registry inspection failed"
  AUTHORITATIVE_TAG_DIGEST="$(manifest_digest "$WORK_DIR/authoritative-manifest.json")"
  validate_digest "$AUTHORITATIVE_TAG_DIGEST"
  [ "$AUTHORITATIVE_TAG_DIGEST" = "$CANDIDATE_REGISTRY_DIGEST" ] || fail "authoritative digest differs from candidate digest"

  verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "private" "authoritative"
  build_publication_evidence "published" "$AUTHORITATIVE_TAG_DIGEST"
  prepare_success_artifact
  PUBLICATION_STATUS="success"
}

publish_existing() {
  PUBLICATION_MODE="existing"
  CANDIDATE_TAG="$(candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT")"

  AUTHORITATIVE_TAG_DIGEST="$(manifest_digest "$WORK_DIR/authoritative-precheck.json")"
  validate_digest "$AUTHORITATIVE_TAG_DIGEST"
  BUILD_METADATA_DIGEST="$AUTHORITATIVE_TAG_DIGEST"
  CANDIDATE_REGISTRY_DIGEST="$AUTHORITATIVE_TAG_DIGEST"
  cp "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/authoritative-manifest.json"
  cp "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/candidate-manifest.json"
  printf '{"containerimage.digest":"%s","publication_mode":"existing"}\n' "$AUTHORITATIVE_TAG_DIGEST" >"$WORK_DIR/build-metadata.json"

  verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "private" "authoritative"
  scan_runtime_and_policy "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST" "$AUTHORITATIVE_TAG_DIGEST"

  SYFT_VERSION_ACTUAL="$(syft version -o json | jq -r '.version')"
  GRYPE_VERSION_ACTUAL="$(grype version -o json | jq -r '.version')"
  VULNERABILITY_DATABASE="$(grype db status -o json | jq -r '.built // .updated // .schemaVersion // "unknown"')"
  [ "$POLICY_DECISION" = "PASS" ] || fail "existing publication vulnerability policy did not pass"

  build_publication_evidence "existing" "$AUTHORITATIVE_TAG_DIGEST"
  prepare_success_artifact
  PUBLICATION_STATUS="success"
}

publish() {
  ROOT="$(git rev-parse --show-toplevel)"
  cd "$ROOT"
  WORK_DIR="${TRUSTED_PUBLICATION_WORK_DIR:-${RUNNER_TEMP:?}/trusted-publication}"
  RESULT_FILE="${TRUSTED_PUBLICATION_RESULT_FILE:-$WORK_DIR/result.env}"
  DOCKER_AUTH_DIR="$WORK_DIR/docker-config"
  TOOLS_DIR="$WORK_DIR/tools"
  ARTIFACT_NAME="trusted-publication-${GITHUB_SHA:?}-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
  mkdir -p "$WORK_DIR" "$DOCKER_AUTH_DIR"
  chmod 0700 "$DOCKER_AUTH_DIR"
  export DOCKER_CONFIG="$DOCKER_AUTH_DIR"
  trap cleanup EXIT INT TERM

  require_tool docker
  require_tool jq
  require_tool gh
  require_tool curl
  require_tool sha256sum

  SOURCE_REVISION="${GITHUB_SHA:?}"
  WORKFLOW_RUN_ID="${GITHUB_RUN_ID:?}"
  WORKFLOW_RUN_ATTEMPT="${GITHUB_RUN_ATTEMPT:?}"
  SOURCE_REF="${GITHUB_REF:?}"
  AUTHORITATIVE_TAG="$(authoritative_tag "$SOURCE_REVISION")"
  validate_source_revision "$SOURCE_REVISION"
  [ "$(git rev-parse HEAD)" = "$SOURCE_REVISION" ] || fail "checked-out HEAD does not match trusted source revision"

  printf '%s\n' "${GITHUB_TOKEN:?}" | docker login "$REGISTRY_HOST" -u "${GITHUB_ACTOR:?}" --password-stdin >/dev/null
  LOGIN_ATTEMPTED="true"
  install_evidence_tools

  local precheck_status=0
  set +e
  inspect_registry_reference "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/authoritative-precheck.err"
  precheck_status="$?"
  set -e

  case "$precheck_status" in
    0) publish_existing ;;
    4) publish_first ;;
    *) fail "authoritative pre-build check failed closed" ;;
  esac

  log "trusted publication completed in $PUBLICATION_MODE mode"
}

case "${1:-}" in
  publish)
    publish
    ;;
  *)
    fail "usage: $0 publish"
    ;;
esac
