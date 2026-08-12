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
  }
}.freeze

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

def quoted_name_pattern(name)
  /name:\s+#{Regexp.escape(name)}\s*$/
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
  fail_with("#{path} is missing immutable checkout pin") unless content.include?('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')
  fail_with("#{path} is missing if: always() final gate") unless content.include?('if: ${{ always() }}')

  gate_count = content.scan(quoted_name_pattern(contract[:gate])).length
  fail_with("#{path} must contain exactly one final gate named #{contract[:gate]}") unless gate_count == 1

  runtime_count = content.scan(quoted_name_pattern(contract[:runtime])).length
  fail_with("#{path} must contain exactly one runtime job named #{contract[:runtime]}") unless runtime_count == 1
end

repository_validation = File.read('.github/workflows/validate.yml')
fail_with('Repository Validation must keep required gate name') unless repository_validation.match?(quoted_name_pattern('Validate repository baseline'))
fail_with('Repository Validation pull_request trigger must not use paths') if repository_validation.match?(/^  pull_request:\s*\n\s+paths:/)

puts '[ok] workflow governance validation passed'
