#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'yaml'

class TrustedPublicationWorkflowTest < Minitest::Test
  WORKFLOW = '.github/workflows/trusted-image-publication.yml'
  RUNTIME = 'scripts/supply-chain/trusted-publication.sh'
  CANDIDATE_REPOSITORY = 'ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates'
  AUTHORITATIVE_REPOSITORY = 'ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture'
  SOURCE_REPOSITORY = 'Franklindot04/k8s-internal-developer-platform'

  def workflow
    @workflow ||= YAML.safe_load(File.read(WORKFLOW), aliases: false)
  end

  def workflow_text
    @workflow_text ||= File.read(WORKFLOW)
  end

  def runtime
    @runtime ||= File.read(RUNTIME)
  end

  def package_metadata_valid?(object, expected_visibility)
    object['visibility'] == expected_visibility &&
      object.dig('repository', 'full_name') == SOURCE_REPOSITORY
  end

  def test_event_governance_push_main_only
    trigger = workflow.fetch(true)

    assert_equal({ 'branches' => ['main'] }, trigger.fetch('push'))
    refute_includes(trigger.keys, 'pull_request')
    refute_includes(trigger.keys, 'pull_request_target')
    refute_includes(trigger.keys, 'workflow_dispatch')
    refute_includes(trigger.keys, 'workflow_run')
    refute_includes(trigger.keys, 'schedule')
    refute_includes(trigger.keys, 'release')
  end

  def test_permission_governance
    jobs = workflow.fetch('jobs')

    assert_equal({ 'contents' => 'read' }, workflow.fetch('permissions'))
    assert_equal({ 'contents' => 'read' }, jobs.fetch('scope').fetch('permissions'))
    assert_equal({ 'contents' => 'read', 'packages' => 'write' }, jobs.fetch('candidate').fetch('permissions'))
    assert_equal({ 'contents' => 'read', 'packages' => 'write' }, jobs.fetch('authoritative').fetch('permissions'))
    assert_equal({ 'contents' => 'read' }, jobs.fetch('final-report').fetch('permissions'))
    refute_match(/id-token:\s+write/, workflow_text)
    refute_match(/attestations:\s+write/, workflow_text)
  end

  def test_concurrency_governance
    concurrency = workflow.fetch('concurrency')

    assert_equal('trusted-image-publication', concurrency.fetch('group'))
    assert_equal('max', concurrency.fetch('queue'))
    refute_includes(concurrency.keys, 'cancel-in-progress')
  end

  def test_actions_are_pinned_to_immutable_shas
    refs = workflow_text.scan(/uses:\s+([^\s#]+)/).flatten

    assert_includes(refs, 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1')
    assert_includes(refs, 'actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a')
    assert_includes(refs, 'actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c')
    refs.each do |ref|
      next if ref.start_with?('./')

      assert_match(/@[0-9a-f]{40}\z/, ref)
    end
  end

  def test_runtime_uses_hardened_repositories_and_attempt_identity
    assert_includes(runtime, CANDIDATE_REPOSITORY)
    assert_includes(runtime, AUTHORITATIVE_REPOSITORY)
    assert_includes(runtime, 'candidate_tag "$SOURCE_REVISION" "$WORKFLOW_RUN_ID" "$WORKFLOW_RUN_ATTEMPT"')
    assert_includes(runtime, '--load')
    assert_includes(runtime, '--provenance=false')
    assert_includes(runtime, '--sbom=false')
    assert_includes(runtime, 'docker buildx imagetools create')
    assert_includes(runtime, 'verify_package_metadata "$CANDIDATE_PACKAGE_NAME" "public" "candidate"')
    assert_includes(runtime, 'verify_package_metadata "$AUTHORITATIVE_PACKAGE_NAME" "public" "authoritative"')
    assert_includes(runtime, 'classify_authoritative_publication_state')
    assert_includes(runtime, 'classify_authoritative_package_response')
    assert_includes(runtime, 'classify_authoritative_versions_response')
    assert_includes(runtime, 'LOCAL_POLICY_DECISION')
    assert_includes(runtime, 'docker push "$candidate_ref"')
  end

  def test_authoritative_publication_is_environment_gated
    job = workflow.fetch('jobs').fetch('authoritative')

    assert_equal('authoritative-publication', job.fetch('environment'))
    assert_equal(['candidate'], job.fetch('needs'))
    assert_includes(job.fetch('if'), "needs.candidate.outputs.mode == 'candidate'")
  end

  def test_runtime_forbids_visibility_mutation_and_secret_patterns
    refute_match(/personal_access_token|PERSONAL_ACCESS_TOKEN|REGISTRY_PASSWORD/, runtime)
    refute_match(/id-token:\s+write|attestations:\s+write|cosign|sigstore/, workflow_text)
    refute_match(/\beval\b/, runtime)
    refute_match(/visibility.*(PATCH|mutation|update)|change visibility/i, runtime)
    refute_match(/curl\s+.*-X\s+DELETE|gh api .*--method DELETE|delete package/i, runtime)
  end

  def test_package_metadata_contract
    candidate_public = { 'visibility' => 'public', 'repository' => { 'full_name' => SOURCE_REPOSITORY } }
    candidate_unknown = { 'visibility' => '', 'repository' => { 'full_name' => SOURCE_REPOSITORY } }
    wrong_linkage = { 'visibility' => 'public', 'repository' => { 'full_name' => 'other/repository' } }
    missing = {}

    assert(package_metadata_valid?(candidate_public, 'public'))
    refute(package_metadata_valid?(candidate_unknown, 'public'))
    refute(package_metadata_valid?(wrong_linkage, 'public'))
    refute(package_metadata_valid?(missing, 'public'))
  end

  def test_authoritative_public_visibility_is_required_synthetically
    authoritative_public = { 'visibility' => 'public', 'repository' => { 'full_name' => SOURCE_REPOSITORY } }
    authoritative_private = { 'visibility' => 'private', 'repository' => { 'full_name' => SOURCE_REPOSITORY } }

    assert(package_metadata_valid?(authoritative_public, 'public'))
    refute(package_metadata_valid?(authoritative_private, 'public'))
  end
end
