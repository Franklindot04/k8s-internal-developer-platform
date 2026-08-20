#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'minitest/autorun'
require 'tmpdir'
require_relative 'publication'

class PublicationContractTest < Minitest::Test
  VERSIONS_FILE = 'scripts/supply-chain/versions.env'
  SOURCE = '0123456789abcdef0123456789abcdef01234567'
  RUN_ID = '31757611145'
  RUN_ATTEMPT = '1'
  DIGEST_A = 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  DIGEST_B = 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
  ARCHIVE_SHA = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'

  def versions
    @versions ||= SupplyChainPublication.read_versions(VERSIONS_FILE)
  end

  def sha(value)
    Digest::SHA256.hexdigest(value)
  end

  def base_input(status: 'published', digest: DIGEST_A, policy: 'PASS')
    {
      source_revision: SOURCE,
      workflow_run_id: RUN_ID,
      workflow_run_attempt: RUN_ATTEMPT,
      status: status,
      candidate_repository: SupplyChainPublication::CANDIDATE_REPOSITORY,
      authoritative_repository: SupplyChainPublication::AUTHORITATIVE_REPOSITORY,
      local_state: status == 'existing' ? 'EXISTING_PUBLICATION' : 'LOCAL_VERIFIED',
      local_image_id: digest,
      local_archive_sha256: ARCHIVE_SHA,
      candidate_digest: digest,
      scan_target_digest: digest,
      authoritative_digest: digest,
      syft_version: versions.fetch('SYFT_VERSION').delete_prefix('v'),
      grype_version: versions.fetch('GRYPE_VERSION').delete_prefix('v'),
      cyclonedx_filename: 'sbom.cdx.json',
      cyclonedx_sha256: sha('cyclonedx'),
      syft_json_filename: 'sbom.syft.json',
      syft_json_sha256: sha('syft-json'),
      vulnerability_report_filename: 'vulnerabilities.json',
      vulnerability_report_sha256: sha('vulnerabilities'),
      vulnerability_database: 'synthetic-db',
      policy_result_filename: 'policy-result.json',
      policy_result_sha256: sha('policy-result'),
      policy_decision: policy
    }
  end

  def manifest(input)
    SupplyChainPublication.build_manifest(input, versions_file: VERSIONS_FILE)
  end

  def assert_contract_error(pattern = nil)
    error = assert_raises(SupplyChainPublication::ContractError) { yield }
    assert_match(pattern, error.message) if pattern
  end

  def test_successful_publication_fixture_validates_and_generates_handoff
    Dir.mktmpdir do |dir|
      path = File.join(dir, SupplyChainPublication::PUBLICATION_MANIFEST)
      published = manifest(base_input)
      SupplyChainPublication.write_manifest(path, published)
      validated = SupplyChainPublication.validate_manifest_file!(path, versions_file: VERSIONS_FILE)
      handoff = SupplyChainPublication.build_handoff(validated, SupplyChainPublication.sha256_file(path))

      assert_equal('published', validated.fetch('publication').fetch('status'))
      assert_equal(SupplyChainPublication::CANDIDATE_REPOSITORY, validated.fetch('candidate').fetch('repository'))
      assert_equal(SupplyChainPublication::AUTHORITATIVE_REPOSITORY, validated.fetch('authoritative').fetch('repository'))
      assert_equal(DIGEST_A, handoff.fetch('image').fetch('digest'))
      assert_equal(SupplyChainPublication::AUTHORITATIVE_REPOSITORY, handoff.fetch('image').fetch('repository'))
      assert_equal(SOURCE, handoff.fetch('source').fetch('revision'))
      SupplyChainPublication.validate_handoff_object!(handoff, validated)
    end
  end

  def test_candidate_fixture_validates_but_forbids_handoff
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    input.delete(:authoritative_repository)
    candidate = manifest(input)

    assert_equal('candidate', candidate.fetch('publication').fetch('status'))
    assert(!candidate.key?('authoritative'))
    assert_contract_error(/handoff requires/) do
      SupplyChainPublication.build_handoff(candidate, sha('candidate'))
    end
  end

  def test_policy_blocked_fixture_validates_without_authoritative_or_candidate_digest
    input = base_input(status: 'local_blocked', policy: 'FAIL')
    input[:local_state] = 'LOCAL_BLOCKED'
    input.delete(:authoritative_digest)
    input.delete(:authoritative_repository)
    input.delete(:candidate_digest)
    input.delete(:scan_target_digest)
    blocked = manifest(input)

    assert_equal('local_blocked', blocked.fetch('publication').fetch('status'))
    assert_equal('FAIL', blocked.fetch('vulnerability').fetch('decision'))
    assert_equal('LOCAL_BLOCKED', blocked.fetch('local').fetch('state'))
    assert_equal(false, blocked.fetch('candidate').fetch('published'))
    assert(!blocked.fetch('candidate').key?('digest'))
    assert(!blocked.key?('authoritative'))
    assert_contract_error(/handoff requires/) do
      SupplyChainPublication.build_handoff(blocked, sha('blocked'))
    end
  end

  def test_candidate_scan_digest_mismatch_fails
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    input.delete(:authoritative_repository)
    input[:scan_target_digest] = DIGEST_B

    assert_contract_error(/candidate digest continuity mismatch/) { manifest(input) }
  end

  def test_local_identity_must_not_be_used_as_registry_digest_authority
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    input.delete(:authoritative_repository)
    input[:local_image_id] = DIGEST_B
    input[:local_archive_sha256] = sha('different-local-archive')

    candidate = manifest(input)

    assert_equal(DIGEST_B, candidate.fetch('local').fetch('image_id'))
    assert_equal(DIGEST_A, candidate.fetch('candidate').fetch('digest'))
    assert_equal(DIGEST_A, candidate.fetch('verification').fetch('scan_target_digest'))
  end

  def test_final_digest_mismatch_fails
    input = base_input
    input[:authoritative_digest] = DIGEST_B

    assert_contract_error(/publication digest continuity mismatch/) { manifest(input) }
  end

  def test_handoff_digest_mismatch_fails
    published = manifest(base_input)
    handoff = SupplyChainPublication.build_handoff(published, sha('published'))
    handoff['image']['digest'] = DIGEST_B

    assert_contract_error(/handoff digest mismatch/) do
      SupplyChainPublication.validate_handoff_object!(handoff, published)
    end
  end

  def test_same_source_rerun_match_is_idempotent
    result = SupplyChainPublication.evaluate_transition(
      existing_authoritative_digest: DIGEST_A,
      attempted_digest: DIGEST_A
    )
    assert_equal('RERUN_EXISTING_MATCH', result)
  end

  def test_existing_publication_does_not_claim_new_candidate
    input = base_input(status: 'existing')
    input.delete(:candidate_digest)
    existing = manifest(input)

    assert_equal('existing', existing.fetch('publication').fetch('status'))
    assert_equal('EXISTING_PUBLICATION', existing.fetch('local').fetch('state'))
    assert_equal(false, existing.fetch('candidate').fetch('published'))
    assert(!existing.fetch('candidate').key?('digest'))
    assert_equal(DIGEST_A, existing.fetch('authoritative').fetch('digest'))
  end

  def test_same_source_rerun_mismatch_fails_closed
    result = SupplyChainPublication.evaluate_transition(
      existing_authoritative_digest: DIGEST_A,
      attempted_digest: DIGEST_B
    )
    assert_equal('RERUN_EXISTING_MISMATCH', result)
  end

  def test_malformed_source_revisions_reject
    ['', '1234', SOURCE.upcase, 'main', "0123456789abcdef0123456789abcdef01234567\n", 'g123456789abcdef0123456789abcdef0123456'].each do |value|
      assert_contract_error(/source revision/) { SupplyChainPublication.validate_source_revision!(value) }
    end
  end

  def test_malformed_digests_reject
    [
      DIGEST_A.upcase,
      "sha256:#{'a' * 63}",
      "sha256:#{'a' * 65}",
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      "sha512:#{'a' * 64}",
      'sha-0123456789abcdef0123456789abcdef01234567',
      "#{DIGEST_A}\n"
    ].each do |value|
      assert_contract_error(/digest/) { SupplyChainPublication.validate_digest!(value) }
    end
  end

  def test_unsafe_workflow_run_ids_reject
    ['', '0', '-1', 'run-1', '123:latest', "123\n", 'abc'].each do |value|
      assert_contract_error(/workflow run ID/) { SupplyChainPublication.candidate_tag(SOURCE, value, RUN_ATTEMPT) }
    end
  end

  def test_unsafe_workflow_run_attempts_reject
    ['', '0', '-1', '1.1', '1e2', 'attempt-1', '123:latest', ' 1', "1\n", 'abc'].each do |value|
      assert_contract_error(/workflow run attempt/) { SupplyChainPublication.candidate_tag(SOURCE, RUN_ID, value) }
    end
  end

  def test_large_positive_workflow_run_attempt_is_valid
    tag = SupplyChainPublication.candidate_tag(SOURCE, RUN_ID, '12345678901234567890')

    assert_equal("candidate-#{SOURCE}-run-#{RUN_ID}-attempt-12345678901234567890", tag)
  end

  def test_reference_construction_never_infers_digest_from_tag
    assert_equal(
      "#{SupplyChainPublication::CANDIDATE_REPOSITORY}:candidate-#{SOURCE}-run-#{RUN_ID}-attempt-#{RUN_ATTEMPT}",
      SupplyChainPublication.candidate_reference(
        source_revision: SOURCE,
        workflow_run_id: RUN_ID,
        workflow_run_attempt: RUN_ATTEMPT
      )
    )
    assert_equal(
      "#{SupplyChainPublication::CANDIDATE_REPOSITORY}@#{DIGEST_A}",
      SupplyChainPublication.candidate_digest_reference(DIGEST_A)
    )
    assert_equal(
      "#{SupplyChainPublication::AUTHORITATIVE_REPOSITORY}:sha-#{SOURCE}",
      SupplyChainPublication.authoritative_tag_reference(source_revision: SOURCE)
    )
    assert_equal(
      "#{SupplyChainPublication::AUTHORITATIVE_REPOSITORY}@#{DIGEST_A}",
      SupplyChainPublication.authoritative_digest_reference(DIGEST_A)
    )
  end

  def test_candidate_attempt_collision_regression_is_prevented
    attempt_one = SupplyChainPublication.candidate_tag(SOURCE, RUN_ID, '1')
    attempt_two = SupplyChainPublication.candidate_tag(SOURCE, RUN_ID, '2')

    ref_one = SupplyChainPublication.candidate_reference(
      source_revision: SOURCE,
      workflow_run_id: RUN_ID,
      workflow_run_attempt: '1'
    )
    ref_two = SupplyChainPublication.candidate_reference(
      source_revision: SOURCE,
      workflow_run_id: RUN_ID,
      workflow_run_attempt: '2'
    )

    refute_equal(attempt_one, attempt_two)
    refute_equal(ref_one, ref_two)
  end

  def test_stage_5_image_contract_compatibility_shape
    published = manifest(base_input)
    handoff = SupplyChainPublication.build_handoff(published, sha('published'))
    image = handoff.fetch('image')

    assert_equal(SupplyChainPublication::AUTHORITATIVE_REPOSITORY, image.fetch('repository'))
    assert_match(/\Asha256:[a-f0-9]{64}\z/, image.fetch('digest'))
    assert(!image.fetch('repository').include?('@'))
    assert(!image.fetch('repository').split('/').last.include?(':'))
  end

  def test_candidate_visibility_contract_is_verified_public_staging
    candidate = manifest(base_input(status: 'candidate').tap do |input|
      input.delete(:authoritative_digest)
      input.delete(:authoritative_repository)
    end)

    assert_equal('VERIFIED_PUBLIC_STAGING', candidate.fetch('candidate').fetch('role'))
    assert_equal('public', candidate.fetch('candidate').fetch('expected_visibility'))
    assert_equal(true, candidate.fetch('candidate').fetch('published'))
  end

  def test_handoff_rejects_candidate_repository
    published = manifest(base_input)
    handoff = SupplyChainPublication.build_handoff(published, sha('published'))
    handoff['image']['repository'] = SupplyChainPublication::CANDIDATE_REPOSITORY

    assert_contract_error(/handoff repository mismatch/) do
      SupplyChainPublication.validate_handoff_object!(handoff, published)
    end
  end

  def test_successful_publication_crosses_repositories_with_same_digest
    published = manifest(base_input)
    handoff = SupplyChainPublication.build_handoff(published, sha('published'))

    refute_equal(published.fetch('candidate').fetch('repository'), published.fetch('authoritative').fetch('repository'))
    assert_equal(SupplyChainPublication::CANDIDATE_REPOSITORY, published.fetch('candidate').fetch('repository'))
    assert_equal(SupplyChainPublication::AUTHORITATIVE_REPOSITORY, published.fetch('authoritative').fetch('repository'))
    assert_equal(published.fetch('candidate').fetch('digest'), published.fetch('authoritative').fetch('digest'))
    assert_equal(SupplyChainPublication::AUTHORITATIVE_REPOSITORY, handoff.fetch('image').fetch('repository'))
  end

  def test_candidate_and_authoritative_repository_collapse_fails
    input = base_input
    input[:candidate_repository] = SupplyChainPublication::AUTHORITATIVE_REPOSITORY

    assert_contract_error(/candidate repository/) { manifest(input) }
  end

  def test_candidate_state_using_authoritative_repository_fails
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    input.delete(:authoritative_repository)
    input[:candidate_repository] = SupplyChainPublication::AUTHORITATIVE_REPOSITORY

    assert_contract_error(/candidate repository/) { manifest(input) }
  end

  def test_published_state_using_candidate_as_authoritative_repository_fails
    input = base_input
    input[:authoritative_repository] = SupplyChainPublication::CANDIDATE_REPOSITORY

    assert_contract_error(/authoritative repository/) { manifest(input) }
  end

  def test_candidate_tag_must_match_workflow_run_attempt_metadata
    published = manifest(base_input)
    published['candidate']['tag'] = SupplyChainPublication.candidate_tag(SOURCE, RUN_ID, '2')

    assert_contract_error(/candidate tag mismatch/) do
      SupplyChainPublication.validate_manifest_object!(published, versions_file: VERSIONS_FILE)
    end
  end

  def test_ambiguous_registry_repository_field_fails
    published = manifest(base_input)
    published['registry']['repository'] = SupplyChainPublication::AUTHORITATIVE_REPOSITORY

    assert_contract_error(/ambiguous/) do
      SupplyChainPublication.validate_manifest_object!(published, versions_file: VERSIONS_FILE)
    end
  end

  def test_public_manifest_200_with_valid_digest_exists
    result = SupplyChainPublication.classify_registry_manifest_response(
      http_status: '200',
      headers: "Docker-Content-Digest: #{DIGEST_A}\nContent-Type: application/vnd.oci.image.manifest.v1+json\n",
      body: '{}'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_EXISTS, result.fetch('classification'))
    assert_equal(DIGEST_A, result.fetch('digest'))
  end

  def test_public_manifest_200_without_valid_digest_fails
    [
      '',
      'sha256:not-hex',
      DIGEST_A.upcase
    ].each do |digest|
      result = SupplyChainPublication.classify_registry_manifest_response(
        http_status: '200',
        headers: "Docker-Content-Digest: #{digest}\nContent-Type: application/vnd.oci.image.manifest.v1+json\n",
        body: '{}'
      )

      assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_INVALID_DIGEST, result.fetch('classification'))
    end
  end

  def test_public_manifest_200_with_unsupported_media_type_fails
    result = SupplyChainPublication.classify_registry_manifest_response(
      http_status: '200',
      headers: "Docker-Content-Digest: #{DIGEST_A}\nContent-Type: text/html\n",
      body: '{}'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_MALFORMED, result.fetch('classification'))
  end

  def test_public_manifest_404_known_registry_absence_is_first_publication
    %w[MANIFEST_UNKNOWN NAME_UNKNOWN].each do |code|
      result = SupplyChainPublication.classify_registry_manifest_response(
        http_status: '404',
        headers: "Content-Type: application/json\n",
        body: JSON.generate('errors' => [{ 'code' => code }])
      )

      assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_ABSENT, result.fetch('classification'))
      assert_equal(code, result.fetch('registry_error_code'))
    end
  end

  def test_anonymous_token_403_denied_exact_scope_is_public_unobservable
    result = SupplyChainPublication.classify_registry_token_response(
      http_status: '403',
      body: JSON.generate('errors' => [{ 'code' => 'DENIED' }]),
      mode: 'anonymous'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_UNOBSERVABLE, result.fetch('classification'))
    assert_equal('DENIED', result.fetch('registry_error_code'))
  end

  def test_anonymous_token_403_html_or_unknown_code_fails_closed
    html = SupplyChainPublication.classify_registry_token_response(
      http_status: '403',
      body: '<html>denied</html>',
      mode: 'anonymous'
    )
    unknown = SupplyChainPublication.classify_registry_token_response(
      http_status: '403',
      body: JSON.generate('errors' => [{ 'code' => 'UNEXPECTED' }]),
      mode: 'anonymous'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_MALFORMED, html.fetch('classification'))
    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_DENIED, unknown.fetch('classification'))
  end

  def test_authenticated_token_403_denied_fails_closed
    result = SupplyChainPublication.classify_registry_token_response(
      http_status: '403',
      body: JSON.generate('errors' => [{ 'code' => 'DENIED' }]),
      mode: 'authenticated'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_DENIED, result.fetch('classification'))
  end

  def test_token_failures_fail_closed
    {
      '401' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_AUTH_FAILURE,
      '429' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_RATE_LIMITED,
      '500' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_SERVER_FAILURE,
      '000' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_NETWORK_FAILURE
    }.each do |status, expected|
      result = SupplyChainPublication.classify_registry_token_response(
        http_status: status,
        body: JSON.generate('errors' => [{ 'code' => 'DENIED' }]),
        mode: 'anonymous'
      )
      assert_equal(expected, result.fetch('classification'))
    end
  end

  def test_token_success_requires_token_value
    present = SupplyChainPublication.classify_registry_token_response(
      http_status: '200',
      body: JSON.generate('token' => 'synthetic'),
      mode: 'anonymous'
    )
    missing = SupplyChainPublication.classify_registry_token_response(
      http_status: '200',
      body: JSON.generate('not_token' => 'synthetic'),
      mode: 'anonymous'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_EXISTS, present.fetch('classification'))
    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_AUTH_FAILURE, missing.fetch('classification'))
  end

  def test_public_manifest_404_unknown_or_html_fails_closed
    unknown = SupplyChainPublication.classify_registry_manifest_response(
      http_status: '404',
      headers: "Content-Type: application/json\n",
      body: JSON.generate('errors' => [{ 'code' => 'BLOB_UNKNOWN' }])
    )
    html = SupplyChainPublication.classify_registry_manifest_response(
      http_status: '404',
      headers: "Content-Type: text/html\n",
      body: '<html>missing</html>'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_UNKNOWN, unknown.fetch('classification'))
    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_MALFORMED, html.fetch('classification'))
  end

  def test_public_manifest_http_failures_fail_closed
    {
      '401' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_AUTH_FAILURE,
      '403' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_DENIED,
      '429' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_RATE_LIMITED,
      '500' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_SERVER_FAILURE,
      '503' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_SERVER_FAILURE,
      '000' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_NETWORK_FAILURE,
      '418' => SupplyChainPublication::PUBLIC_AUTHORITATIVE_UNKNOWN
    }.each do |status, expected|
      result = SupplyChainPublication.classify_registry_manifest_response(
        http_status: status,
        headers: "Content-Type: application/json\n",
        body: JSON.generate('errors' => [{ 'code' => 'UNEXPECTED' }])
      )
      assert_equal(expected, result.fetch('classification'))
    end
  end

  def test_public_manifest_malformed_registry_json_fails_closed
    result = SupplyChainPublication.classify_registry_manifest_response(
      http_status: '404',
      headers: "Content-Type: application/json\n",
      body: '{'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_MALFORMED, result.fetch('classification'))
  end

  def test_pre_promotion_absent_is_eligible
    state = SupplyChainPublication.pre_promotion_recheck_state(
      classification: SupplyChainPublication::PUBLIC_AUTHORITATIVE_ABSENT,
      existing_digest: '',
      candidate_digest: DIGEST_A
    )

    assert_equal(SupplyChainPublication::PRE_PROMOTION_ABSENT, state)
  end

  def test_pre_promotion_same_digest_is_idempotent
    state = SupplyChainPublication.pre_promotion_recheck_state(
      classification: SupplyChainPublication::PUBLIC_AUTHORITATIVE_EXISTS,
      existing_digest: DIGEST_A,
      candidate_digest: DIGEST_A
    )

    assert_equal(SupplyChainPublication::PRE_PROMOTION_EXISTS_SAME_DIGEST, state)
  end

  def test_pre_promotion_different_digest_fails_closed
    state = SupplyChainPublication.pre_promotion_recheck_state(
      classification: SupplyChainPublication::PUBLIC_AUTHORITATIVE_EXISTS,
      existing_digest: DIGEST_B,
      candidate_digest: DIGEST_A
    )

    assert_equal(SupplyChainPublication::PRE_PROMOTION_EXISTS_DIFFERENT_DIGEST, state)
  end

  def test_pre_promotion_failures_remain_failures
    [
      SupplyChainPublication::PUBLIC_AUTHORITATIVE_AUTH_FAILURE,
      SupplyChainPublication::PUBLIC_AUTHORITATIVE_NETWORK_FAILURE,
      SupplyChainPublication::PUBLIC_AUTHORITATIVE_MALFORMED,
      SupplyChainPublication::PUBLIC_AUTHORITATIVE_UNOBSERVABLE
    ].each do |classification|
      state = SupplyChainPublication.pre_promotion_recheck_state(
        classification: classification,
        existing_digest: '',
        candidate_digest: DIGEST_A
      )
      assert_equal(classification, state)
    end
  end
end
