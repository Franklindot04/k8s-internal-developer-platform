#!/usr/bin/env ruby
# frozen_string_literal: true

REQUIRED_FILES = [
  'scripts/supply-chain/versions.env',
  'scripts/supply-chain/install-evidence-tools.sh',
  'scripts/supply-chain/evidence.sh',
  'scripts/supply-chain/evaluate-vulnerabilities.rb',
  'scripts/supply-chain/publication.rb',
  'scripts/supply-chain/test-publication.rb',
  'scripts/supply-chain/validate-publication.rb',
  'scripts/supply-chain/validate-evidence.rb',
  'tests/fixtures/supply-chain-policy/no-findings.json',
  'tests/fixtures/supply-chain-policy/high-only.json',
  'tests/fixtures/supply-chain-policy/critical.json',
  'tests/fixtures/supply-chain-policy/critical-unfixed.json',
  'tests/fixtures/supply-chain-policy/unknown-only.json',
  'tests/fixtures/supply-chain-policy/malformed.json'
].freeze

FORBIDDEN_PATTERNS = {
  /curl[[:space:]]+[^|]*\|[[:space:]]*(sh|bash)/ => 'curl-pipe-shell',
  /\bsudo\b/ => 'sudo',
  %r{(/usr/local/bin|/usr/bin|/opt/homebrew/bin)} => 'global install location',
  /\bdocker[[:space:]]+login\b/ => 'docker login',
  /\bdocker[[:space:]]+push\b/ => 'docker push',
  /packages:[[:space:]]*write/ => 'packages write permission',
  /\bghcr\b/ => 'GHCR registry behavior',
  /\bcosign\b/ => 'signing behavior',
  /\bid-token:[[:space:]]*write/ => 'OIDC write permission',
  /attestations:[[:space:]]*write/ => 'attestation write permission',
  /pull_request_target/ => 'pull_request_target workflow behavior'
}.freeze

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

REQUIRED_FILES.each do |path|
  fail_with("required Stage 6C1 file missing: #{path}") unless File.file?(path)
end

versions = {}
File.readlines('scripts/supply-chain/versions.env', chomp: true).each do |line|
  next if line.empty? || line.start_with?('#')

  key, value = line.split('=', 2)
  fail_with("malformed versions metadata line: #{line}") unless key && value
  versions[key] = value
end

%w[SYFT_VERSION SYFT_ASSET SYFT_SHA256 GRYPE_VERSION GRYPE_ASSET GRYPE_SHA256].each do |key|
  fail_with("missing versions metadata: #{key}") unless versions[key]
  fail_with("empty versions metadata: #{key}") if versions[key].empty?
end

%w[SYFT_SHA256 GRYPE_SHA256 SYFT_DARWIN_ARM64_SHA256 GRYPE_DARWIN_ARM64_SHA256].each do |key|
  next unless versions[key]

  fail_with("malformed SHA-256 for #{key}") unless versions[key].match?(/\A[0-9a-f]{64}\z/)
end

versions.each do |key, value|
  fail_with("#{key} must not use latest") if value.downcase.include?('latest')
end

scan_paths = Dir.glob('{scripts/supply-chain,tests/fixtures/supply-chain-policy}/**/*', File::FNM_EXTGLOB).select { |path| File.file?(path) }
scan_paths.reject! { |path| path == 'scripts/supply-chain/validate-evidence-tooling.rb' }
publication_contract_files = [
  'scripts/supply-chain/publication.rb',
  'scripts/supply-chain/test-publication.rb',
  'scripts/supply-chain/validate-publication.rb'
]
scan_paths.reject! { |path| publication_contract_files.include?(path) }
trusted_publication_runtime = 'scripts/supply-chain/trusted-publication.sh'
scan_paths.reject! { |path| path == trusted_publication_runtime }
scan_paths.reject! { |path| path == 'scripts/supply-chain/test-trusted-publication-workflow.rb' }
scan_paths.each do |path|
  content = File.readlines(path).reject { |line| line.start_with?('#!') }.join
  FORBIDDEN_PATTERNS.each do |pattern, description|
    fail_with("#{path} contains forbidden #{description}") if content.match?(pattern)
  end
end

publication_contract_files.each do |path|
  content = File.readlines(path).reject { |line| line.start_with?('#!') }.join
  {
    /\bdocker[[:space:]]+login\b/ => 'docker login',
    /\bdocker[[:space:]]+push\b/ => 'docker push',
    /packages:[[:space:]]*write/ => 'packages write permission',
    /\bcosign\b/ => 'signing behavior',
    /\bid-token:[[:space:]]*write/ => 'OIDC write permission',
    /attestations:[[:space:]]*write/ => 'attestation write permission',
    /pull_request_target/ => 'pull_request_target workflow behavior'
  }.each do |pattern, description|
    fail_with("#{path} contains forbidden #{description}") if content.match?(pattern)
  end
end

publication_contract = File.read('scripts/supply-chain/publication.rb')
fail_with('publication contract must lock the candidate GHCR repository') unless publication_contract.include?('ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates')
fail_with('publication contract must lock the authoritative GHCR repository') unless publication_contract.include?('ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture')
fail_with('publication contract must name candidate and authoritative repositories separately') unless publication_contract.include?('CANDIDATE_REPOSITORY') && publication_contract.include?('AUTHORITATIVE_REPOSITORY')
fail_with('publication contract must validate repository separation') unless publication_contract.include?('validate_repository_separation!')
fail_with('publication contract must validate source revision') unless publication_contract.include?('validate_source_revision!')
fail_with('publication contract must validate registry digests') unless publication_contract.include?('validate_digest!')
fail_with('publication contract must construct attempt-aware candidate tags') unless publication_contract.include?('candidate-') && publication_contract.include?('-attempt-')
fail_with('publication contract must construct authoritative source tags') unless publication_contract.include?('sha-')
fail_with('publication contract must model rerun mismatch') unless publication_contract.include?('RERUN_EXISTING_MISMATCH')
fail_with('publication contract must keep handoff authoritative-only') unless publication_contract.include?("handoff.fetch('image').fetch('repository') == AUTHORITATIVE_REPOSITORY")
if File.file?('.github/workflows/trusted-image-publication.yml')
  workflow = File.read('.github/workflows/trusted-image-publication.yml')
  fail_with('trusted publication workflow must be push-to-main only') unless workflow.include?("push:") && workflow.include?("- main")
  fail_with('trusted publication workflow must not run on pull_request') if workflow.match?(/^\s+pull_request:/)
  fail_with('trusted publication workflow must not use workflow_dispatch initially') if workflow.match?(/^\s+workflow_dispatch:/)
end

if File.file?(trusted_publication_runtime)
  runtime = File.read(trusted_publication_runtime)
  fail_with('trusted publication runtime must use strict shell mode') unless runtime.include?('set -Eeuo pipefail')
  fail_with('trusted publication runtime must use GITHUB_TOKEN') unless runtime.include?('GITHUB_TOKEN')
  fail_with('trusted publication runtime must not mention PAT') if runtime.match?(/(^|[^A-Z])(PAT|GHCR_PAT|REGISTRY_PAT)([^A-Z]|$)|personal_access_token|PERSONAL_ACCESS_TOKEN/)
  fail_with('trusted publication runtime must use docker login password-stdin') unless runtime.include?('--password-stdin')
  fail_with('trusted publication runtime must logout from GHCR') unless runtime.include?('docker logout "$REGISTRY_HOST"')
  fail_with('trusted publication runtime must isolate Docker config') unless runtime.include?('DOCKER_CONFIG')
  fail_with('trusted publication runtime must verify candidate package as public staging') unless runtime.include?('verify_package_metadata "$CANDIDATE_PACKAGE_NAME" "public" "candidate"')
  fail_with('trusted publication runtime must verify authoritative package as public') unless runtime.include?('verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "public" "authoritative"')
  fail_with('trusted publication runtime must not enumerate user package namespaces for candidate precheck') if runtime.include?('/users/Franklindot04/packages?package_type=container') || runtime.include?('GITHUB_PACKAGES_API_ROOT')
  fail_with('trusted publication runtime must use public registry manifest precheck') unless runtime.include?('classify_authoritative_manifest_state')
  fail_with('trusted publication runtime must classify registry manifest responses') unless runtime.include?('classify_registry_manifest_response')
  fail_with('trusted publication runtime must classify registry token responses') unless runtime.include?('classify_registry_token_response')
  fail_with('trusted publication runtime must model public-unobservable unpublished state') unless runtime.include?('PUBLIC_AUTHORITATIVE_UNOBSERVABLE')
  fail_with('publication contract must keep public-unobservable distinct from absence') unless publication_contract.include?('PUBLIC_AUTHORITATIVE_UNOBSERVABLE')
  fail_with('trusted publication runtime must require exact GHCR pull scope') unless runtime.include?('repository:$AUTHORITATIVE_REGISTRY_PATH:pull')
  fail_with('trusted publication runtime must support registry bearer token challenge flow') unless runtime.include?('registry_bearer_token')
  fail_with('trusted publication runtime must emit safe precheck telemetry') unless runtime.include?('precheck_stage=')
  fail_with('trusted publication runtime must fail closed on token/auth/network states') unless runtime.include?('PUBLIC_AUTHORITATIVE_AUTH_FAILURE') && runtime.include?('PUBLIC_AUTHORITATIVE_NETWORK_FAILURE')
  fail_with('trusted publication runtime must perform authoritative pre-promotion recheck') unless runtime.include?('pre_promotion_recheck_state') && runtime.include?('authoritative pre-promotion recheck failed closed')
  fail_with('publication contract must classify only explicit registry absence codes as absent') unless publication_contract.include?('MANIFEST_UNKNOWN') && publication_contract.include?('NAME_UNKNOWN')
  fail_with('trusted publication runtime must model local policy before candidate push') unless runtime.include?('LOCAL_POLICY_DECISION') && runtime.index('LOCAL_POLICY_DECISION') < runtime.index('docker push "$candidate_ref"')
  fail_with('trusted publication runtime must perform authenticated source check after local policy') unless runtime.include?('classify_authoritative_manifest_state "authenticated" "authenticated-source-check"') && runtime.index('[ "$LOCAL_POLICY_DECISION" = "PASS" ] || fail "local vulnerability policy did not pass"') < runtime.index('classify_authoritative_manifest_state "authenticated" "authenticated-source-check"')
  fail_with('trusted publication runtime must perform authenticated source check before candidate push') unless runtime.index('classify_authoritative_manifest_state "authenticated" "authenticated-source-check"') < runtime.index('docker push "$candidate_ref"')
  fail_with('trusted publication runtime must use runner-local quarantine build load') unless runtime.include?('--load')
  fail_with('trusted publication runtime must classify local image IDs as local evidence only') unless runtime.include?('LOCAL_EXECUTION_EVIDENCE_ONLY')
  fail_with('trusted publication runtime must use attempt-aware candidate tags') unless runtime.include?('candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT"')
  fail_with('trusted publication runtime must not use latest tags') if runtime.match?(/:latest|latest/)
  fail_with('trusted publication runtime must not mutate package visibility') if runtime.match?(/visibility.*(PATCH|mutation|update)|change visibility/i)
  fail_with('trusted publication runtime must not delete packages') if runtime.match?(/curl\s+.*-X\s+DELETE|gh api .*--method DELETE|delete package/i)
  fail_with('trusted publication runtime must not use eval') if runtime.match?(/\beval\b/)
  fail_with('trusted publication runtime must not request signing') if runtime.match?(/cosign|sigstore/)
  fail_with('trusted publication runtime must keep BuildKit provenance disabled') unless runtime.include?('--provenance=false')
  fail_with('trusted publication runtime must keep BuildKit SBOM disabled') unless runtime.include?('--sbom=false')
end

evidence_script = File.read('scripts/supply-chain/evidence.sh')
fixture_dockerfile = File.read('tests/fixtures/supply-chain-fixture/Dockerfile')
fail_with('fixture Dockerfile must carry the repository OCI source label') unless fixture_dockerfile.include?('org.opencontainers.image.source="https://github.com/Franklindot04/k8s-internal-developer-platform"')
fail_with('evidence script must produce CycloneDX portable SBOM') unless evidence_script.include?('cyclonedx-json=')
fail_with('evidence script must produce Syft scanner-native SBOM') unless evidence_script.include?('syft-json=')
fail_with('evidence script must scan the exact Docker archive') unless evidence_script.include?('docker-archive:$(basename "$ARCHIVE")')
fail_with('evidence script must use Buildx load for Docker-driver portability') unless evidence_script.include?('--load')
fail_with('evidence script must save the loaded image into the archive') unless evidence_script.include?('docker image save --output "$ARCHIVE" "$IMAGE_TAG"')
fail_with('evidence script must remove the local tag before archive reload') unless evidence_script.include?('docker image rm "$IMAGE_TAG"')
fail_with('evidence script must load the exact Docker archive') unless evidence_script.include?('docker load --input "$ARCHIVE"')
fail_with('evidence script must record the built Docker image ID') unless evidence_script.include?('built Docker image ID')
fail_with('evidence script must compare built and loaded image IDs') unless evidence_script.include?('loaded image ID differs from built image ID')
fail_with('evidence script must not use Docker exporter direct archive output') if evidence_script.include?('type=docker,dest=')
fail_with('evidence script must not create a custom Buildx builder') if evidence_script.match?(/\bdocker[[:space:]]+buildx[[:space:]]+create\b/)
fail_with('evidence script must perform exactly one application Buildx build') unless evidence_script.scan(/\bdocker[[:space:]]+buildx[[:space:]]+build\b/).length == 1
fail_with('evidence script must not scan CycloneDX SBOM') if evidence_script.include?('sbom:$(basename "$SBOM")')
fail_with('evidence script must not use scanner SBOM as vulnerability authority') if evidence_script.include?('sbom:$(basename "$SCANNER_SBOM")')

allowed_supply_chain_workflows = ['.github/workflows/supply-chain-pr.yml']
supply_chain_workflows = Dir.glob('.github/workflows/*supply-chain*')
unexpected_supply_chain_workflows = supply_chain_workflows - allowed_supply_chain_workflows
if unexpected_supply_chain_workflows.any?
  fail_with("unexpected supply-chain workflow file(s): #{unexpected_supply_chain_workflows.join(', ')}")
end

puts '[ok] supply-chain evidence tooling static validation passed'
