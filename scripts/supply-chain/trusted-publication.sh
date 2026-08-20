#!/usr/bin/env bash
set -Eeuo pipefail

readonly REGISTRY_HOST="ghcr.io"
readonly SOURCE_REPOSITORY="Franklindot04/k8s-internal-developer-platform"
readonly CANDIDATE_REPOSITORY="ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates"
readonly AUTHORITATIVE_REPOSITORY="ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture"
readonly TARGET_PLATFORM="linux/amd64"
readonly CANDIDATE_PACKAGE_NAME="k8s-internal-developer-platform%2Fsupply-chain-fixture-candidates"
readonly AUTHORITATIVE_PACKAGE_NAME="k8s-internal-developer-platform%2Fsupply-chain-fixture"
readonly GITHUB_PACKAGES_API_ROOT="https://api.github.com/users/Franklindot04/packages/container"
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

classify_authoritative_package_response() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'puts SupplyChainPublication.classify_authoritative_package_response(ARGV.fetch(0), File.read(ARGV.fetch(1)))' "$1" "$2"
}

classify_authoritative_versions_response() {
  ruby -r ./scripts/supply-chain/publication.rb -e 'puts SupplyChainPublication.classify_authoritative_versions_response(ARGV.fetch(0), File.read(ARGV.fetch(1)), source_tag: ARGV.fetch(2))' "$1" "$2" "$3"
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
    printf 'local_policy_decision=%s\n' "${LOCAL_POLICY_DECISION:-}"
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

github_packages_api_get() {
  local path="$1"
  local output="$2"
  local error_file="$3"
  local http_status=""

  set +e
  http_status="$(
    curl --silent --show-error --location \
      --output "$output" \
      --write-out '%{http_code}' \
      --header 'Accept: application/vnd.github+json' \
      --header "Authorization: Bearer ${GITHUB_TOKEN:?}" \
      --header 'X-GitHub-Api-Version: 2026-03-10' \
      "${GITHUB_PACKAGES_API_ROOT}${path}" 2>"$error_file"
  )"
  local curl_status="$?"
  set -e

  if [ "$curl_status" -ne 0 ]; then
    printf '000\n'
    return 0
  fi

  printf '%s\n' "$http_status"
}

classify_authoritative_publication_state() {
  local package_body="$WORK_DIR/authoritative-package-precheck.json"
  local package_error="$WORK_DIR/authoritative-package-precheck.err"
  local package_status=""
  local package_classification=""

  package_status="$(github_packages_api_get "/$AUTHORITATIVE_PACKAGE_NAME" "$package_body" "$package_error")"
  package_classification="$(classify_authoritative_package_response "$package_status" "$package_body")"

  case "$package_classification" in
    AUTHORITATIVE_PACKAGE_ABSENT)
      return 4
      ;;
    AUTHORITATIVE_PACKAGE_EXISTS)
      ;;
    *)
      return 1
      ;;
  esac

  local page=1
  local tag_seen="false"
  while :; do
    local versions_body="$WORK_DIR/authoritative-versions-page-${page}.json"
    local versions_error="$WORK_DIR/authoritative-versions-page-${page}.err"
    local versions_status=""
    local versions_classification=""

    versions_status="$(github_packages_api_get "/$AUTHORITATIVE_PACKAGE_NAME/versions?per_page=100&page=$page" "$versions_body" "$versions_error")"
    versions_classification="$(classify_authoritative_versions_response "$versions_status" "$versions_body" "$AUTHORITATIVE_TAG")"

    case "$versions_classification" in
      AUTHORITATIVE_SOURCE_TAG_EXISTS)
        if [ "$tag_seen" = "true" ]; then
          return 1
        fi
        tag_seen="true"
        ;;
      AUTHORITATIVE_SOURCE_TAG_ABSENT)
        if [ "$(jq 'length' "$versions_body")" -eq 0 ]; then
          break
        fi
        ;;
      *)
        return 1
        ;;
    esac

    page=$((page + 1))
  done

  if [ "$tag_seen" = "true" ]; then
    return 0
  fi

  return 4
}

manifest_digest() {
  jq -r '.digest // empty' "$1"
}

manifest_media_type() {
  jq -r '.mediaType // empty' "$1"
}

docker_login() {
  printf '%s\n' "${GITHUB_TOKEN:?}" | docker login "$REGISTRY_HOST" -u "${GITHUB_ACTOR:?}" --password-stdin >/dev/null
  LOGIN_ATTEMPTED="true"
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
  local output="$2"

  bash scripts/supply-chain/fixture.sh smoke-image "$image_ref"
  printf '{"health":"PASS","expected_response":"PASS","runtime_user":"65532:65532","non_root":"PASS","graceful_shutdown":"PASS","exit_code":0,"cleanup":"PASS"}\n' >"$output"
}

generate_sbom_and_vulnerability() {
  local archive="$1"
  local prefix="$2"

  syft "docker-archive:$(basename "$archive")" -o cyclonedx-json="$WORK_DIR/${prefix}-sbom.cdx.json" -o syft-json="$WORK_DIR/${prefix}-sbom.syft.json"
  grype "docker-archive:$(basename "$archive")" -o json >"$WORK_DIR/${prefix}-vulnerabilities.json"

  set +e
  ruby scripts/supply-chain/evaluate-vulnerabilities.rb "$WORK_DIR/${prefix}-vulnerabilities.json" "$WORK_DIR/${prefix}-policy-result.json"
  local policy_exit="$?"
  set -e

  local decision=""
  decision="$(jq -r '.decision // empty' "$WORK_DIR/${prefix}-policy-result.json")"
  [ "$decision" = "PASS" ] || [ "$decision" = "FAIL" ] || fail "vulnerability policy did not produce a valid decision"
  [ "$policy_exit" -eq 0 ] || [ "$decision" = "FAIL" ] || fail "vulnerability policy evaluator failed"

  if [ "$prefix" = "local" ]; then
    LOCAL_POLICY_DECISION="$decision"
  else
    POLICY_DECISION="$decision"
  fi
}

copy_evidence_set() {
  local prefix="$1"

  cp "$WORK_DIR/${prefix}-sbom.cdx.json" "$WORK_DIR/sbom.cdx.json"
  cp "$WORK_DIR/${prefix}-sbom.syft.json" "$WORK_DIR/sbom.syft.json"
  cp "$WORK_DIR/${prefix}-vulnerabilities.json" "$WORK_DIR/vulnerabilities.json"
  cp "$WORK_DIR/${prefix}-policy-result.json" "$WORK_DIR/policy-result.json"
}

verify_artifact_size() {
  local file="$1"
  local size=""
  size="$(wc -c <"$file" | tr -d ' ')"
  [ "$size" -le "$MAX_EVIDENCE_BYTES" ] || fail "evidence file too large: $(basename "$file")"
}

build_publication_evidence() {
  local status="$1"
  local local_state="$2"
  local authoritative_digest="${3:-}"
  local evidence_path="$WORK_DIR/publication-evidence.json"
  local handoff_path="$WORK_DIR/image-reference.json"

  PUBLICATION_STATUS="$status" \
    LOCAL_STATE="$local_state" \
    AUTHORITATIVE_TAG_DIGEST="$authoritative_digest" \
    CYCLONEDX_PATH="$WORK_DIR/sbom.cdx.json" \
    SYFT_JSON_PATH="$WORK_DIR/sbom.syft.json" \
    VULNERABILITY_PATH="$WORK_DIR/vulnerabilities.json" \
    POLICY_RESULT_PATH="$WORK_DIR/policy-result.json" \
    PUBLICATION_EVIDENCE_PATH="$evidence_path" \
    HANDOFF_PATH="$handoff_path" \
    ruby -r ./scripts/supply-chain/publication.rb -e '
    status = ENV.fetch("PUBLICATION_STATUS")
    input = {
      source_revision: ENV.fetch("SOURCE_REVISION"),
      workflow_run_id: ENV.fetch("WORKFLOW_RUN_ID"),
      workflow_run_attempt: ENV.fetch("WORKFLOW_RUN_ATTEMPT"),
      status: status,
      candidate_repository: SupplyChainPublication::CANDIDATE_REPOSITORY,
      authoritative_repository: SupplyChainPublication::AUTHORITATIVE_REPOSITORY,
      local_state: ENV.fetch("LOCAL_STATE"),
      local_image_id: ENV.fetch("LOCAL_IMAGE_ID"),
      local_archive_sha256: ENV.fetch("LOCAL_ARCHIVE_SHA256"),
      candidate_digest: ENV["CANDIDATE_REGISTRY_DIGEST"],
      scan_target_digest: ENV["VERIFIED_SCAN_TARGET_DIGEST"],
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
    input.delete(:candidate_digest) if %w[local_blocked existing].include?(status)
    input.delete(:scan_target_digest) if status == "local_blocked"
    input.delete(:authoritative_repository) unless %w[published existing].include?(status)
    input.delete(:authoritative_digest) unless %w[published existing].include?(status)
    manifest = SupplyChainPublication.build_manifest(input, versions_file: "scripts/supply-chain/versions.env")
    SupplyChainPublication.write_manifest(ENV.fetch("PUBLICATION_EVIDENCE_PATH"), manifest)
    if %w[published existing].include?(status)
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

prepare_artifact() {
  local include_handoff="${1:-false}"
  local stage="$WORK_DIR/artifact"
  mkdir -p "$stage"
  cp "$WORK_DIR/publication-evidence.json" "$stage/"
  cp "$WORK_DIR/publication-evidence.json.sha256" "$stage/"
  cp "$WORK_DIR/sbom.cdx.json" "$stage/"
  cp "$WORK_DIR/sbom.syft.json" "$stage/"
  cp "$WORK_DIR/vulnerabilities.json" "$stage/"
  cp "$WORK_DIR/policy-result.json" "$stage/"
  cp "$WORK_DIR/local-runtime-proof.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/registry-runtime-proof.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/runtime-proof.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/local-build-metadata.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/local-image.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/candidate-manifest.json" "$stage/" 2>/dev/null || true
  cp "$WORK_DIR/authoritative-manifest.json" "$stage/" 2>/dev/null || true
  if [ "$include_handoff" = "true" ]; then
    cp "$WORK_DIR/image-reference.json" "$stage/"
  fi
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

anonymous_pull_by_digest() {
  local digest_ref="$1"
  local anonymous_config="$WORK_DIR/anonymous-docker-config"
  mkdir -p "$anonymous_config"
  chmod 0700 "$anonymous_config"
  DOCKER_CONFIG="$anonymous_config" docker pull "$digest_ref"
}

record_tool_versions() {
  SYFT_VERSION_ACTUAL="$(syft version -o json | jq -r '.version')"
  GRYPE_VERSION_ACTUAL="$(grype version -o json | jq -r '.version')"
  VULNERABILITY_DATABASE="$(grype db status -o json | jq -r '.built // .updated // .schemaVersion // "unknown"')"
}

build_local_candidate() {
  local local_ref="$1"
  local archive="$2"

  docker buildx build \
    --platform "$TARGET_PLATFORM" \
    --provenance=false \
    --sbom=false \
    --load \
    --tag "$local_ref" \
    --metadata-file "$WORK_DIR/local-build-metadata.json" \
    tests/fixtures/supply-chain-fixture

  LOCAL_IMAGE_ID="$(docker image inspect "$local_ref" --format '{{.Id}}')"
  validate_digest "$LOCAL_IMAGE_ID"
  printf '{"local_image_id":"%s","identity_authority":"LOCAL_EXECUTION_EVIDENCE_ONLY"}\n' "$LOCAL_IMAGE_ID" >"$WORK_DIR/local-image.json"
  write_runtime_proof "$local_ref" "$WORK_DIR/local-runtime-proof.json"
  docker image save --output "$archive" "$local_ref"
  LOCAL_ARCHIVE_SHA256="$(sha256_file "$archive")"
}

run_existing() {
  PUBLICATION_MODE="existing"
  CANDIDATE_TAG="$(candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT")"
  docker_login
  retry 10 inspect_registry_reference "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/authoritative-precheck.err" || fail "authoritative registry inspection failed"
  AUTHORITATIVE_TAG_DIGEST="$(manifest_digest "$WORK_DIR/authoritative-precheck.json")"
  validate_digest "$AUTHORITATIVE_TAG_DIGEST"
  VERIFIED_SCAN_TARGET_DIGEST="$AUTHORITATIVE_TAG_DIGEST"
  LOCAL_IMAGE_ID="$AUTHORITATIVE_TAG_DIGEST"
  LOCAL_ARCHIVE_SHA256="$(printf '%s' "$AUTHORITATIVE_TAG_DIGEST" | sha256sum | awk '{ print $1 }')"
  cp "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/authoritative-manifest.json"
  cp "$WORK_DIR/authoritative-precheck.json" "$WORK_DIR/candidate-manifest.json"

  verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "public" "authoritative"
  pull_and_verify_exact_digest "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST" "$AUTHORITATIVE_TAG_DIGEST"
  anonymous_pull_by_digest "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST"
  write_runtime_proof "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST" "$WORK_DIR/runtime-proof.json"
  local archive="$WORK_DIR/existing-authoritative.tar"
  docker image save --output "$archive" "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST"
  LOCAL_ARCHIVE_SHA256="$(sha256_file "$archive")"
  (cd "$WORK_DIR" && generate_sbom_and_vulnerability "$archive" "registry")
  copy_evidence_set "registry"
  record_tool_versions
  [ "$POLICY_DECISION" = "PASS" ] || fail "existing publication vulnerability policy did not pass"

  build_publication_evidence "existing" "EXISTING_PUBLICATION" "$AUTHORITATIVE_TAG_DIGEST"
  prepare_artifact "true"
  PUBLICATION_STATUS="success"
}

run_candidate() {
  PUBLICATION_MODE="candidate"
  CANDIDATE_TAG="$(candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT")"
  local local_ref="supply-chain-fixture-local:${SOURCE_REVISION}"
  local candidate_ref="$CANDIDATE_REPOSITORY:$CANDIDATE_TAG"
  local candidate_digest_ref=""
  local local_archive="$WORK_DIR/local-supply-chain-fixture.tar"
  local registry_archive="$WORK_DIR/registry-supply-chain-fixture.tar"

  build_local_candidate "$local_ref" "$local_archive"
  (cd "$WORK_DIR" && generate_sbom_and_vulnerability "$local_archive" "local")
  record_tool_versions

  if [ "$LOCAL_POLICY_DECISION" = "FAIL" ]; then
    POLICY_DECISION="FAIL"
    copy_evidence_set "local"
    build_publication_evidence "local_blocked" "LOCAL_BLOCKED"
    prepare_artifact "false"
    fail "local vulnerability policy blocked candidate publication"
  fi
  [ "$LOCAL_POLICY_DECISION" = "PASS" ] || fail "local vulnerability policy did not pass"

  docker_login
  docker tag "$local_ref" "$candidate_ref"
  docker push "$candidate_ref"

  retry 10 inspect_registry_reference "$candidate_ref" "$WORK_DIR/candidate-manifest.json" "$WORK_DIR/candidate-inspect.err" || fail "candidate registry inspection failed"
  CANDIDATE_REGISTRY_DIGEST="$(manifest_digest "$WORK_DIR/candidate-manifest.json")"
  CANDIDATE_MEDIA_TYPE="$(manifest_media_type "$WORK_DIR/candidate-manifest.json")"
  validate_digest "$CANDIDATE_REGISTRY_DIGEST"
  [ -n "$CANDIDATE_MEDIA_TYPE" ] || fail "candidate manifest media type missing"

  verify_package_metadata "$CANDIDATE_PACKAGE_NAME" "public" "candidate"
  candidate_digest_ref="$CANDIDATE_REPOSITORY@$CANDIDATE_REGISTRY_DIGEST"
  pull_and_verify_exact_digest "$candidate_digest_ref" "$CANDIDATE_REGISTRY_DIGEST"
  write_runtime_proof "$candidate_digest_ref" "$WORK_DIR/registry-runtime-proof.json"
  docker image save --output "$registry_archive" "$candidate_digest_ref"
  (cd "$WORK_DIR" && generate_sbom_and_vulnerability "$registry_archive" "registry")
  copy_evidence_set "registry"
  [ "$POLICY_DECISION" = "PASS" ] || fail "post-push vulnerability policy blocked authoritative publication"

  build_publication_evidence "candidate" "LOCAL_VERIFIED"
  prepare_artifact "false"
  PUBLICATION_STATUS="success"
}

run_authoritative() {
  PUBLICATION_MODE="authoritative"
  local candidate_evidence="${TRUSTED_PUBLICATION_CANDIDATE_EVIDENCE:?}"
  ruby scripts/supply-chain/validate-publication.rb validate-publication --publication "$candidate_evidence"

  SOURCE_REVISION="$(jq -r '.source.revision' "$candidate_evidence")"
  WORKFLOW_RUN_ID="$(jq -r '.workflow.run_id' "$candidate_evidence")"
  WORKFLOW_RUN_ATTEMPT="$(jq -r '.workflow.run_attempt' "$candidate_evidence")"
  CANDIDATE_TAG="$(jq -r '.candidate.tag' "$candidate_evidence")"
  CANDIDATE_REGISTRY_DIGEST="$(jq -r '.candidate.digest' "$candidate_evidence")"
  LOCAL_IMAGE_ID="$(jq -r '.local.image_id' "$candidate_evidence")"
  LOCAL_ARCHIVE_SHA256="$(jq -r '.local.archive_sha256' "$candidate_evidence")"
  POLICY_DECISION="$(jq -r '.vulnerability.decision' "$candidate_evidence")"
  LOCAL_POLICY_DECISION="PASS"
  AUTHORITATIVE_TAG="$(authoritative_tag "$SOURCE_REVISION")"
  validate_source_revision "$SOURCE_REVISION"
  validate_digest "$CANDIDATE_REGISTRY_DIGEST"
  [ "$POLICY_DECISION" = "PASS" ] || fail "candidate evidence policy did not pass"

  docker_login
  docker buildx imagetools create \
    --prefer-index=false \
    --metadata-file "$WORK_DIR/promotion-metadata.json" \
    --tag "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" \
    "$CANDIDATE_REPOSITORY@$CANDIDATE_REGISTRY_DIGEST"

  retry 10 inspect_registry_reference "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG" "$WORK_DIR/authoritative-manifest.json" "$WORK_DIR/authoritative-inspect.err" || fail "authoritative registry inspection failed"
  AUTHORITATIVE_TAG_DIGEST="$(manifest_digest "$WORK_DIR/authoritative-manifest.json")"
  validate_digest "$AUTHORITATIVE_TAG_DIGEST"
  [ "$AUTHORITATIVE_TAG_DIGEST" = "$CANDIDATE_REGISTRY_DIGEST" ] || fail "authoritative digest differs from candidate digest"

  verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "public" "authoritative"
  anonymous_pull_by_digest "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST"

  cp "$candidate_evidence" "$WORK_DIR/candidate-publication-evidence.json"
  cp "$(dirname "$candidate_evidence")/sbom.cdx.json" "$WORK_DIR/sbom.cdx.json"
  cp "$(dirname "$candidate_evidence")/sbom.syft.json" "$WORK_DIR/sbom.syft.json"
  cp "$(dirname "$candidate_evidence")/vulnerabilities.json" "$WORK_DIR/vulnerabilities.json"
  cp "$(dirname "$candidate_evidence")/policy-result.json" "$WORK_DIR/policy-result.json"
  cp "$(dirname "$candidate_evidence")/candidate-manifest.json" "$WORK_DIR/candidate-manifest.json"
  record_tool_versions
  VERIFIED_SCAN_TARGET_DIGEST="$CANDIDATE_REGISTRY_DIGEST"
  build_publication_evidence "published" "LOCAL_VERIFIED" "$AUTHORITATIVE_TAG_DIGEST"
  prepare_artifact "true"
  PUBLICATION_STATUS="success"
}

initialize() {
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
  AUTHORITATIVE_TAG="$(authoritative_tag "$SOURCE_REVISION")"
  validate_source_revision "$SOURCE_REVISION"
  [ "$(git rev-parse HEAD)" = "$SOURCE_REVISION" ] || fail "checked-out HEAD does not match trusted source revision"
}

candidate_command() {
  initialize
  ARTIFACT_NAME="trusted-publication-candidate-${GITHUB_SHA:?}-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
  install_evidence_tools

  local precheck_status=0
  set +e
  classify_authoritative_publication_state
  precheck_status="$?"
  set -e

  case "$precheck_status" in
    0) run_existing ;;
    4) run_candidate ;;
    *) fail "authoritative pre-build check failed closed" ;;
  esac

  log "trusted candidate completed in $PUBLICATION_MODE mode"
}

authoritative_command() {
  initialize
  ARTIFACT_NAME="trusted-publication-authoritative-${GITHUB_SHA:?}-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
  install_evidence_tools
  run_authoritative
  log "authoritative publication completed"
}

case "${1:-}" in
  candidate)
    candidate_command
    ;;
  authoritative)
    authoritative_command
    ;;
  *)
    fail "usage: $0 {candidate|authoritative}"
    ;;
esac
