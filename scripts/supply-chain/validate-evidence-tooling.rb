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
fail_with('publication contract must not create a trusted workflow') if File.file?('.github/workflows/trusted-image-publication.yml')

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
