#!/usr/bin/env ruby
# frozen_string_literal: true

WORKFLOWS = {
  '.github/workflows/local-kubernetes.yml' => {
    gate: 'Kind lifecycle validation',
    runtime: 'Kind lifecycle execution'
  },
  '.github/workflows/gitops-control-plane.yml' => {
    gate: 'Argo CD reconciliation validation',
    runtime: 'Argo CD reconciliation execution'
  },
  '.github/workflows/golden-path-helm.yml' => {
    gate: 'Helm chart and GitOps validation',
    runtime: 'Helm chart and GitOps execution'
  },
  '.github/workflows/service-gitops.yml' => {
    gate: 'Service GitOps validation',
    runtime: 'Service GitOps execution'
  },
  '.github/workflows/supply-chain-pr.yml' => {
    gate: 'Supply-chain PR validation',
    runtime: 'Supply-chain PR execution'
  }
}.freeze

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

def quoted_name_pattern(name)
  /name:\s+#{Regexp.escape(name)}\s*$/
end

def assert_immutable_action_pins(path, content)
  content.scan(/uses:\s+([^\s#]+)/).flatten.each do |action|
    next if action.start_with?('./')

    ref = action.split('@', 2)[1]
    fail_with("#{path} uses an unpinned action: #{action}") unless ref&.match?(/\A[0-9a-f]{40}\z/)
  end
end

def assert_no_write_permissions(path, content)
  forbidden = %w[
    actions
    artifact-metadata
    attestations
    checks
    contents
    deployments
    id-token
    packages
    pull-requests
    security-events
    statuses
  ]

  forbidden.each do |permission|
    fail_with("#{path} grants #{permission}: write") if content.match?(/^\s+#{Regexp.escape(permission)}:\s+write\s*$/)
  end
end

def assert_supply_chain_pr_workflow(content)
  path = '.github/workflows/supply-chain-pr.yml'

  fail_with("#{path} must not define push trigger") if content.match?(/^  push:\s*$/)
  fail_with("#{path} must not define workflow_dispatch trigger") if content.match?(/^  workflow_dispatch:\s*$/)
  fail_with("#{path} must not define schedule trigger") if content.match?(/^  schedule:\s*$/)
  fail_with("#{path} must not define workflow_run trigger") if content.match?(/^  workflow_run:\s*$/)
  fail_with("#{path} is missing supply-chain scope classifier") unless content.include?('scripts/ci/workflow-scope.sh supply-chain-pr')
  fail_with("#{path} is missing execution timeout") unless content.include?('timeout-minutes: 25')
  fail_with("#{path} is missing final gate timeout") unless content.scan(/timeout-minutes:\s+5/).length >= 2
  fail_with("#{path} must use continue-on-error only for evidence run") unless content.scan(/continue-on-error:\s+true/).length == 1
  fail_with("#{path} must validate evidence after the aggregate run") unless content.include?('ruby scripts/supply-chain/validate-evidence.rb validate')
  fail_with("#{path} must upload image archive artifact") unless content.include?('name: ${{ env.IMAGE_ARTIFACT_NAME }}')
  fail_with("#{path} must upload evidence artifact") unless content.include?('name: ${{ env.EVIDENCE_ARTIFACT_NAME }}')
  fail_with("#{path} must use 7-day image retention") unless content.include?('retention-days: 7')
  fail_with("#{path} must use 14-day evidence retention") unless content.include?('retention-days: 14')
  fail_with("#{path} must fail when upload paths are absent") unless content.scan(/if-no-files-found:\s+error/).length == 2
  fail_with("#{path} must not enable hidden file upload") if content.include?('include-hidden-files: true')
  upload_path_blocks = []
  lines = content.lines
  lines.each_with_index do |line, index|
    next unless line.match?(/^\s+path:\s*(.*)$/)

    block = [Regexp.last_match(1)]
    cursor = index + 1
    while cursor < lines.length && lines[cursor].match?(/^\s{12,}\S/)
      block << lines[cursor]
      cursor += 1
    end
    upload_path_blocks << block.join
  end
  fail_with("#{path} must not upload .tmp directly") if upload_path_blocks.any? { |block| block.include?('.tmp/') }
  fail_with("#{path} must not upload broad temporary state") if content.include?('.tmp/**')
  fail_with("#{path} is missing image size guard") unless content.include?('IMAGE_ARCHIVE_MAX_BYTES: "52428800"')
  fail_with("#{path} is missing evidence size guard") unless content.include?('EVIDENCE_MAX_BYTES: "10485760"')
  fail_with("#{path} must not dump the full GitHub context") if content.include?('toJSON(github)') || content.include?('toJson(github)')
  fail_with("#{path} must not use PR comments") if content.match?(/gh\s+pr\s+comment|pull-requests:\s+write/)
  fail_with("#{path} must not upload SARIF") if content.include?('upload-sarif')
  fail_with("#{path} must not publish registry images") if content.match?(/docker\s+(login|push)|ghcr\.io/)
  fail_with("#{path} must not configure a custom Buildx builder") if content.match?(/docker\/setup-buildx-action|docker\s+buildx\s+create/)
  fail_with("#{path} must not request OIDC") if content.match?(/id-token:\s+write/)
  fail_with("#{path} must not add signing or attestations") if content.match?(/cosign|sigstore|attestation|attestations:\s+write|provenance/)
  fail_with("#{path} must not use runner context in job-level env") if content.include?('ARTIFACT_STAGING_DIR: ${{ runner.temp }}')
  fail_with("#{path} has a summary printf format beginning with -") if content.match?(/printf\s+'-/)
end

def assert_trusted_publication_workflow
  path = '.github/workflows/trusted-image-publication.yml'
  fail_with("#{path} is missing") unless File.file?(path)

  content = File.read(path)
  fail_with("#{path} must not define pull_request trigger") if content.match?(/^  pull_request:\s*$/)
  fail_with("#{path} must not define pull_request_target trigger") if content.include?('pull_request_target')
  fail_with("#{path} must not define workflow_dispatch trigger") if content.match?(/^  workflow_dispatch:\s*$/)
  fail_with("#{path} must not define workflow_run trigger") if content.match?(/^  workflow_run:\s*$/)
  fail_with("#{path} must not define schedule trigger") if content.match?(/^  schedule:\s*$/)
  fail_with("#{path} must trigger on push") unless content.match?(/^  push:\s*$/)
  fail_with("#{path} must trigger only main branch pushes") unless content.match?(/branches:\n\s+- main/)
  fail_with("#{path} must use contents read baseline") unless content.match?(/permissions:\n\s+contents:\s+read/)
  assert_immutable_action_pins(path, content)
  fail_with("#{path} is missing immutable checkout pin") unless content.include?('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')
  fail_with("#{path} is missing immutable upload-artifact pin") unless content.include?('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a')
  fail_with("#{path} must classify trusted publication scope") unless content.include?('scripts/ci/workflow-scope.sh trusted-publication')
  fail_with("#{path} must not use workflow-level paths filtering") if content.match?(/^\s+paths:\s*$/)
  fail_with("#{path} must use ubuntu-24.04") unless content.scan(/runs-on:\s+ubuntu-24\.04/).length >= 3
  fail_with("#{path} must use publication timeout") unless content.include?('timeout-minutes: 30')
  fail_with("#{path} must use trusted publication concurrency group") unless content.match?(/concurrency:\n\s+group:\s+trusted-image-publication/)
  fail_with("#{path} must use queue max") unless content.match?(/concurrency:\n\s+group:\s+trusted-image-publication\n\s+queue:\s+max/)
  fail_with("#{path} must serialize the full trusted publication transaction at workflow level") unless content.match?(/^concurrency:\n\s+group:\s+trusted-image-publication\n\s+queue:\s+max/m)
  fail_with("#{path} must not use queue single") if content.match?(/queue:\s+single/)
  fail_with("#{path} must not cancel publication runs") if content.include?('cancel-in-progress')
  fail_with("#{path} must not request OIDC") if content.match?(/id-token:\s+write/)
  fail_with("#{path} must not request attestations") if content.match?(/attestations:\s+write/)
  fail_with("#{path} must not add signing") if content.match?(/cosign|sigstore/)
  fail_with("#{path} must not use PAT secrets") if content.match?(/PAT|personal_access_token|PERSONAL_ACCESS_TOKEN|REGISTRY_PASSWORD/)
  fail_with("#{path} must use GITHUB_TOKEN only") unless content.include?('GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}')
  fail_with("#{path} must not grant contents write") if content.match?(/contents:\s+write/)
  fail_with("#{path} must not grant pull request write") if content.match?(/pull-requests:\s+write/)
  fail_with("#{path} must not grant checks write") if content.match?(/checks:\s+write/)
  fail_with("#{path} must not grant statuses write") if content.match?(/statuses:\s+write/)
  fail_with("#{path} must not grant security events write") if content.match?(/security-events:\s+write/)
  fail_with("#{path} must grant packages write exactly twice") unless content.scan(/packages:\s+write/).length == 2
  fail_with("#{path} must gate authoritative publication with protected environment name") unless content.include?('environment: authoritative-publication')
  fail_with("#{path} is missing immutable download-artifact pin") unless content.include?('actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c')

  scope_block = content[/  scope:\n.*?\n\n  candidate:/m]
  candidate_block = content[/  candidate:\n.*?\n\n  authoritative:/m]
  authoritative_block = content[/  authoritative:\n.*?\n\n  final-report:/m]
  final_block = content[/  final-report:\n.*\z/m]
  fail_with("#{path} missing scope job") unless scope_block
  fail_with("#{path} missing candidate job") unless candidate_block
  fail_with("#{path} missing authoritative job") unless authoritative_block
  fail_with("#{path} missing final report job") unless final_block
  fail_with("#{path} scope job must not receive packages write") if scope_block.include?('packages: write')
  fail_with("#{path} final job must not receive packages write") if final_block.include?('packages: write')
  fail_with("#{path} candidate job must receive packages write") unless candidate_block.include?("packages: write")
  fail_with("#{path} authoritative job must receive packages write") unless authoritative_block.include?("packages: write")
  fail_with("#{path} candidate job must run only when trusted-publication scope is true") unless candidate_block.include?("needs.scope.outputs.trusted-publication == 'true'")
  fail_with("#{path} authoritative job must wait for candidate evidence") unless authoritative_block.include?('Download candidate evidence')
  fail_with("#{path} authoritative job must run only for newly verified candidates") unless authoritative_block.include?("needs.candidate.outputs.mode == 'candidate'")
  fail_with("#{path} final report must use if always") unless final_block.include?('if: ${{ always() }}')
  fail_with("#{path} must not upload broad temporary state") if content.include?('$RUNNER_TEMP/**') || content.include?('/tmp/**')
  fail_with("#{path} must not upload Docker archives") if content.match?(/\.tar\b|supply-chain-fixture\.tar/)
end

WORKFLOWS.each do |path, contract|
  content = File.read(path)

  pull_request_index = content.index(/^  pull_request:\s*$/)
  fail_with("#{path} does not define a pull_request trigger") unless pull_request_index

  next_trigger = content[pull_request_index + 1..]&.match(/^  [a-zA-Z_]+:\s*$/)
  pull_request_block = next_trigger ? content[pull_request_index...pull_request_index + next_trigger.begin(0) + 1] : content[pull_request_index..]
  fail_with("#{path} still has workflow-level pull_request paths") if pull_request_block.match?(/^\s+paths:\s*$/)
  fail_with("#{path} still has workflow-level pull_request paths-ignore") if pull_request_block.match?(/^\s+paths-ignore:\s*$/)
  fail_with("#{path} uses pull_request_target") if content.include?('pull_request_target')
  fail_with("#{path} is missing contents: read permission") unless content.match?(/permissions:\n\s+contents:\s+read/)
  assert_no_write_permissions(path, content)
  assert_immutable_action_pins(path, content)
  fail_with("#{path} is missing immutable checkout pin") unless content.include?('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')
  fail_with("#{path} is missing if: always() final gate") unless content.include?('if: ${{ always() }}')

  gate_count = content.scan(quoted_name_pattern(contract[:gate])).length
  fail_with("#{path} must contain exactly one final gate named #{contract[:gate]}") unless gate_count == 1

  runtime_count = content.scan(quoted_name_pattern(contract[:runtime])).length
  fail_with("#{path} must contain exactly one runtime job named #{contract[:runtime]}") unless runtime_count == 1
end

assert_supply_chain_pr_workflow(File.read('.github/workflows/supply-chain-pr.yml'))
assert_trusted_publication_workflow if File.file?('.github/workflows/trusted-image-publication.yml')

repository_validation = File.read('.github/workflows/validate.yml')
fail_with('Repository Validation must keep required gate name') unless repository_validation.match?(quoted_name_pattern('Validate repository baseline'))
fail_with('Repository Validation pull_request trigger must not use paths') if repository_validation.match?(/^  pull_request:\s*\n\s+paths:/)

puts '[ok] workflow governance validation passed'
