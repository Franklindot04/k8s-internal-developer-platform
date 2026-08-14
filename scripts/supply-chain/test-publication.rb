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
      repository: SupplyChainPublication::REPOSITORY,
      build_metadata_digest: digest,
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
      assert_equal(DIGEST_A, handoff.fetch('image').fetch('digest'))
      assert_equal(SupplyChainPublication::REPOSITORY, handoff.fetch('image').fetch('repository'))
      assert_equal(SOURCE, handoff.fetch('source').fetch('revision'))
      SupplyChainPublication.validate_handoff_object!(handoff, validated)
    end
  end

  def test_candidate_fixture_validates_but_forbids_handoff
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    candidate = manifest(input)

    assert_equal('candidate', candidate.fetch('publication').fetch('status'))
    assert(!candidate.key?('authoritative'))
    assert_contract_error(/handoff requires/) do
      SupplyChainPublication.build_handoff(candidate, sha('candidate'))
    end
  end

  def test_policy_blocked_fixture_validates_without_authoritative_fields
    input = base_input(status: 'blocked', policy: 'FAIL')
    input.delete(:authoritative_digest)
    blocked = manifest(input)

    assert_equal('blocked', blocked.fetch('publication').fetch('status'))
    assert_equal('FAIL', blocked.fetch('vulnerability').fetch('decision'))
    assert(!blocked.key?('authoritative'))
    assert_contract_error(/handoff requires/) do
      SupplyChainPublication.build_handoff(blocked, sha('blocked'))
    end
  end

  def test_candidate_scan_digest_mismatch_fails
    input = base_input(status: 'candidate')
    input.delete(:authoritative_digest)
    input[:scan_target_digest] = DIGEST_B

    assert_contract_error(/candidate digest continuity mismatch/) { manifest(input) }
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
      assert_contract_error(/workflow run ID/) { SupplyChainPublication.candidate_tag(SOURCE, value) }
    end
  end

  def test_reference_construction_never_infers_digest_from_tag
    assert_equal(
      "#{SupplyChainPublication::REPOSITORY}:candidate-#{SOURCE}-run-#{RUN_ID}",
      SupplyChainPublication.candidate_reference(source_revision: SOURCE, workflow_run_id: RUN_ID)
    )
    assert_equal(
      "#{SupplyChainPublication::REPOSITORY}@#{DIGEST_A}",
      SupplyChainPublication.candidate_digest_reference(DIGEST_A)
    )
    assert_equal(
      "#{SupplyChainPublication::REPOSITORY}:sha-#{SOURCE}",
      SupplyChainPublication.authoritative_tag_reference(source_revision: SOURCE)
    )
    assert_equal(
      "#{SupplyChainPublication::REPOSITORY}@#{DIGEST_A}",
      SupplyChainPublication.authoritative_digest_reference(DIGEST_A)
    )
  end

  def test_stage_5_image_contract_compatibility_shape
    published = manifest(base_input)
    handoff = SupplyChainPublication.build_handoff(published, sha('published'))
    image = handoff.fetch('image')

    assert_equal(SupplyChainPublication::REPOSITORY, image.fetch('repository'))
    assert_match(/\Asha256:[a-f0-9]{64}\z/, image.fetch('digest'))
    assert(!image.fetch('repository').include?('@'))
    assert(!image.fetch('repository').split('/').last.include?(':'))
  end
end
