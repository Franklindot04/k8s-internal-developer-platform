#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'fileutils'

module SupplyChainPublication
  REGISTRY_HOST = 'ghcr.io'
  CANDIDATE_REPOSITORY = 'ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture-candidates'
  AUTHORITATIVE_REPOSITORY = 'ghcr.io/franklindot04/k8s-internal-developer-platform/supply-chain-fixture'
  AUTHORITATIVE_PACKAGE_NAME = 'k8s-internal-developer-platform/supply-chain-fixture'
  SOURCE_REPOSITORY = 'Franklindot04/k8s-internal-developer-platform'
  SOURCE_URL = 'https://github.com/Franklindot04/k8s-internal-developer-platform'
  TARGET_PLATFORM = 'linux/amd64'
  PUBLICATION_SCHEMA_VERSION = 'idp/supply-chain-publication/v1alpha1'
  HANDOFF_API_VERSION = 'idp/supply-chain-image-reference/v1alpha1'
  HANDOFF_KIND = 'TrustedImageReference'
  PUBLICATION_MANIFEST = 'publication-evidence.json'
  HANDOFF_FILE = 'image-reference.json'
  ALLOWED_STATUSES = %w[local_blocked candidate published existing].freeze
  LOCAL_STATES = %w[LOCAL_VERIFIED LOCAL_BLOCKED EXISTING_PUBLICATION].freeze
  VULNERABILITY_EVIDENCE_SOURCES = {
    'local_blocked' => 'LOCAL_QUARANTINE_SCAN',
    'candidate' => 'VERIFIED_CANDIDATE_POST_PUSH',
    'published' => 'VERIFIED_CANDIDATE_POST_PUSH',
    'existing' => 'EXISTING_AUTHORITATIVE_SCAN'
  }.freeze
  PASS = 'PASS'
  FAIL = 'FAIL'
  PUBLIC_AUTHORITATIVE_EXISTS = 'PUBLIC_AUTHORITATIVE_EXISTS'
  PUBLIC_AUTHORITATIVE_ABSENT = 'PUBLIC_AUTHORITATIVE_ABSENT'
  PUBLIC_AUTHORITATIVE_AUTH_FAILURE = 'PUBLIC_AUTHORITATIVE_AUTH_FAILURE'
  PUBLIC_AUTHORITATIVE_DENIED = 'PUBLIC_AUTHORITATIVE_DENIED'
  PUBLIC_AUTHORITATIVE_RATE_LIMITED = 'PUBLIC_AUTHORITATIVE_RATE_LIMITED'
  PUBLIC_AUTHORITATIVE_SERVER_FAILURE = 'PUBLIC_AUTHORITATIVE_SERVER_FAILURE'
  PUBLIC_AUTHORITATIVE_NETWORK_FAILURE = 'PUBLIC_AUTHORITATIVE_NETWORK_FAILURE'
  PUBLIC_AUTHORITATIVE_MALFORMED = 'PUBLIC_AUTHORITATIVE_MALFORMED'
  PUBLIC_AUTHORITATIVE_UNKNOWN = 'PUBLIC_AUTHORITATIVE_UNKNOWN'
  PUBLIC_AUTHORITATIVE_INVALID_DIGEST = 'PUBLIC_AUTHORITATIVE_INVALID_DIGEST'
  PUBLIC_AUTHORITATIVE_UNOBSERVABLE = 'PUBLIC_AUTHORITATIVE_UNOBSERVABLE'
  PRE_PROMOTION_ABSENT = 'PRE_PROMOTION_ABSENT'
  PRE_PROMOTION_EXISTS_SAME_DIGEST = 'PRE_PROMOTION_EXISTS_SAME_DIGEST'
  PRE_PROMOTION_EXISTS_DIFFERENT_DIGEST = 'PRE_PROMOTION_EXISTS_DIFFERENT_DIGEST'

  class ContractError < StandardError; end

  module_function

  def fail_contract(message)
    raise ContractError, message
  end

  def validate_source_revision!(value)
    fail_contract('source revision must be a 40-character lowercase Git SHA') unless value.is_a?(String)
    fail_contract('source revision must be a 40-character lowercase Git SHA') unless value.match?(/\A[0-9a-f]{40}\z/)

    value
  end

  def validate_workflow_run_id!(value)
    fail_contract('workflow run ID must be a positive integer string') unless value.is_a?(String)
    fail_contract('workflow run ID must be a positive integer string') unless value.match?(/\A[1-9][0-9]*\z/)

    value
  end

  def validate_workflow_run_attempt!(value)
    fail_contract('workflow run attempt must be a positive integer string') unless value.is_a?(String)
    fail_contract('workflow run attempt must be a positive integer string') unless value.match?(/\A[1-9][0-9]*\z/)

    value
  end

  def validate_digest!(value)
    fail_contract('digest must be sha256:<64 lowercase hex>') unless value.is_a?(String)
    fail_contract('digest must be sha256:<64 lowercase hex>') unless value.match?(/\Asha256:[a-f0-9]{64}\z/)

    value
  end

  def validate_sha256_hex!(value)
    fail_contract('SHA-256 checksum must be 64 lowercase hex characters') unless value.is_a?(String)
    fail_contract('SHA-256 checksum must be 64 lowercase hex characters') unless value.match?(/\A[a-f0-9]{64}\z/)

    value
  end

  def validate_registry_repository_shape!(value, role:)
    fail_contract("#{role} repository must be a string") unless value.is_a?(String)
    fail_contract("#{role} repository must not include an embedded digest") if value.include?('@')
    fail_contract("#{role} repository must use GHCR") unless value.start_with?("#{REGISTRY_HOST}/")

    path = value.delete_prefix("#{REGISTRY_HOST}/")
    fail_contract("#{role} repository path must be lowercase") unless path == path.downcase
    fail_contract("#{role} repository path must not include empty segments") if path.split('/').any?(&:empty?)
    fail_contract("#{role} repository path must not include a tag suffix") if path.split('/').last.include?(':')

    value
  end

  def validate_candidate_repository!(value)
    validate_registry_repository_shape!(value, role: 'candidate')
    fail_contract("candidate repository must be #{CANDIDATE_REPOSITORY}") unless value == CANDIDATE_REPOSITORY
    fail_contract('candidate repository must differ from authoritative repository') if value == AUTHORITATIVE_REPOSITORY

    value
  end

  def validate_authoritative_repository!(value)
    validate_registry_repository_shape!(value, role: 'authoritative')
    fail_contract("authoritative repository must be #{AUTHORITATIVE_REPOSITORY}") unless value == AUTHORITATIVE_REPOSITORY
    fail_contract('authoritative repository must differ from candidate repository') if value == CANDIDATE_REPOSITORY

    value
  end

  def validate_repository_separation!(candidate_repository:, authoritative_repository:)
    candidate = validate_candidate_repository!(candidate_repository)
    authoritative = validate_authoritative_repository!(authoritative_repository)
    fail_contract('candidate and authoritative repositories must be different') if candidate == authoritative

    [candidate, authoritative]
  end

  def authoritative_tag(source_revision)
    "sha-#{validate_source_revision!(source_revision)}"
  end

  def parse_http_headers(header_text)
    headers = {}
    header_text.to_s.each_line do |line|
      key, value = line.split(':', 2)
      next if value.nil?

      headers[key.downcase] = value.strip
    end
    headers
  end

  def registry_error_code(body)
    parsed = JSON.parse(body.to_s)
    errors = parsed['errors']
    return nil unless errors.is_a?(Array) && errors.length == 1 && errors.first.is_a?(Hash)

    errors.first['code']
  rescue JSON::ParserError
    :malformed
  end

  def registry_manifest_classification_for_status(status, code)
    return PUBLIC_AUTHORITATIVE_NETWORK_FAILURE if status == '000'
    return PUBLIC_AUTHORITATIVE_AUTH_FAILURE if status == '401'
    return PUBLIC_AUTHORITATIVE_DENIED if status == '403'
    return PUBLIC_AUTHORITATIVE_RATE_LIMITED if status == '429'
    return PUBLIC_AUTHORITATIVE_SERVER_FAILURE if status.match?(/\A5[0-9][0-9]\z/)
    return PUBLIC_AUTHORITATIVE_ABSENT if status == '404' && %w[NAME_UNKNOWN MANIFEST_UNKNOWN].include?(code)
    return PUBLIC_AUTHORITATIVE_MALFORMED if status == '404' && code == :malformed

    PUBLIC_AUTHORITATIVE_UNKNOWN
  end

  def classify_registry_token_response(http_status:, body:, mode:)
    status = http_status.to_s
    error_code = registry_error_code(body)

    if status == '200'
      parsed = begin
        JSON.parse(body.to_s)
      rescue JSON::ParserError
        return { 'classification' => PUBLIC_AUTHORITATIVE_MALFORMED, 'registry_error_code' => 'malformed' }
      end
      token = parsed['token'] || parsed['access_token']
      return { 'classification' => PUBLIC_AUTHORITATIVE_EXISTS, 'registry_error_code' => 'none' } if token.is_a?(String) && !token.empty?

      return { 'classification' => PUBLIC_AUTHORITATIVE_AUTH_FAILURE, 'registry_error_code' => 'none' }
    end

    classification =
      if status == '403' && error_code == 'DENIED' && mode == 'anonymous'
        PUBLIC_AUTHORITATIVE_UNOBSERVABLE
      elsif error_code == :malformed
        PUBLIC_AUTHORITATIVE_MALFORMED
      else
        registry_manifest_classification_for_status(status, error_code)
      end

    {
      'classification' => classification,
      'registry_error_code' => error_code == :malformed ? 'malformed' : (error_code || 'none')
    }
  end

  def classify_registry_manifest_response(http_status:, headers:, body:)
    status = http_status.to_s
    parsed_headers = headers.is_a?(Hash) ? headers.transform_keys { |key| key.to_s.downcase } : parse_http_headers(headers)
    error_code = registry_error_code(body)

    if status == '200'
      digest = parsed_headers['docker-content-digest'].to_s
      return { 'classification' => PUBLIC_AUTHORITATIVE_INVALID_DIGEST, 'registry_error_code' => 'none' } unless digest.match?(/\Asha256:[a-f0-9]{64}\z/)

      media_type = parsed_headers['content-type'].to_s.split(';').first
      supported_media_types = [
        'application/vnd.oci.image.manifest.v1+json',
        'application/vnd.oci.image.index.v1+json',
        'application/vnd.docker.distribution.manifest.v2+json',
        'application/vnd.docker.distribution.manifest.list.v2+json'
      ]
      unless supported_media_types.include?(media_type)
        return { 'classification' => PUBLIC_AUTHORITATIVE_MALFORMED, 'registry_error_code' => 'none', 'digest' => digest }
      end

      return {
        'classification' => PUBLIC_AUTHORITATIVE_EXISTS,
        'registry_error_code' => 'none',
        'digest' => digest,
        'media_type' => media_type
      }
    end

    {
      'classification' => registry_manifest_classification_for_status(status, error_code),
      'registry_error_code' => error_code == :malformed ? 'malformed' : (error_code || 'none')
    }
  end

  def pre_promotion_recheck_state(classification:, existing_digest:, candidate_digest:)
    candidate = validate_digest!(candidate_digest)
    case classification
    when PUBLIC_AUTHORITATIVE_ABSENT
      PRE_PROMOTION_ABSENT
    when PUBLIC_AUTHORITATIVE_EXISTS
      existing = validate_digest!(existing_digest)
      existing == candidate ? PRE_PROMOTION_EXISTS_SAME_DIGEST : PRE_PROMOTION_EXISTS_DIFFERENT_DIGEST
    else
      classification
    end
  end

  def candidate_tag(source_revision, workflow_run_id, workflow_run_attempt)
    source = validate_source_revision!(source_revision)
    run_id = validate_workflow_run_id!(workflow_run_id)
    run_attempt = validate_workflow_run_attempt!(workflow_run_attempt)

    "candidate-#{source}-run-#{run_id}-attempt-#{run_attempt}"
  end

  def candidate_reference(source_revision:, workflow_run_id:, workflow_run_attempt:, repository: CANDIDATE_REPOSITORY)
    "#{validate_candidate_repository!(repository)}:#{candidate_tag(source_revision, workflow_run_id, workflow_run_attempt)}"
  end

  def candidate_digest_reference(digest, repository: CANDIDATE_REPOSITORY)
    "#{validate_candidate_repository!(repository)}@#{validate_digest!(digest)}"
  end

  def authoritative_tag_reference(source_revision:, repository: AUTHORITATIVE_REPOSITORY)
    "#{validate_authoritative_repository!(repository)}:#{authoritative_tag(source_revision)}"
  end

  def authoritative_digest_reference(digest, repository: AUTHORITATIVE_REPOSITORY)
    "#{validate_authoritative_repository!(repository)}@#{validate_digest!(digest)}"
  end

  def evaluate_transition(existing_authoritative_digest:, attempted_digest:)
    existing = existing_authoritative_digest.nil? ? nil : validate_digest!(existing_authoritative_digest)
    attempted = validate_digest!(attempted_digest)

    return 'UNPUBLISHED' if existing.nil?
    return 'RERUN_EXISTING_MATCH' if existing == attempted

    'RERUN_EXISTING_MISMATCH'
  end

  def validate_local_image_id!(value)
    validate_digest!(value)
  end

  def validate_local_state!(value)
    fail_contract('invalid local verification state') unless LOCAL_STATES.include?(value)

    value
  end

  def validate_candidate_continuity!(candidate_registry_digest:, verified_scan_target_digest:)
    digests = [
      validate_digest!(candidate_registry_digest),
      validate_digest!(verified_scan_target_digest)
    ]
    fail_contract('candidate digest continuity mismatch') unless digests.uniq.length == 1

    digests.first
  end

  def validate_complete_continuity!(
    candidate_registry_digest:,
    verified_scan_target_digest:,
    authoritative_tag_digest:,
    handoff_digest:
  )
    digests = [
      validate_digest!(candidate_registry_digest),
      validate_digest!(verified_scan_target_digest),
      validate_digest!(authoritative_tag_digest),
      validate_digest!(handoff_digest)
    ]
    fail_contract('publication digest continuity mismatch') unless digests.uniq.length == 1

    digests.first
  end

  def read_versions(path)
    versions = {}
    File.readlines(path, chomp: true).each do |line|
      next if line.empty? || line.start_with?('#')

      key, value = line.split('=', 2)
      versions[key] = value
    end
    versions
  end

  def normalize_version(value)
    value.to_s.sub(/\Av/, '')
  end

  def validate_vulnerability_database!(value)
    fail_contract('vulnerability database metadata missing') unless value.is_a?(String)
    fail_contract('vulnerability database metadata missing') if value.empty?
    fail_contract('vulnerability database metadata malformed') unless value.match?(/\A[0-9A-Za-z._:+-]+\z/)

    value
  end

  def validate_vulnerability_evidence_source!(value, status)
    expected = VULNERABILITY_EVIDENCE_SOURCES.fetch(status)
    fail_contract('vulnerability evidence source mismatch') unless value == expected

    value
  end

  def sha256_file(path)
    fail_contract("file missing: #{path}") unless File.file?(path)

    Digest::SHA256.file(path).hexdigest
  end

  def read_json(path)
    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    fail_contract("malformed JSON #{path}: #{e.message}")
  end

  def evidence_file(filename, sha256)
    {
      'filename' => filename,
      'sha256' => validate_sha256_hex!(sha256)
    }
  end

  def build_manifest(input, versions_file:)
    versions = read_versions(versions_file)
    source_revision = validate_source_revision!(input.fetch(:source_revision))
    workflow_run_id = validate_workflow_run_id!(input.fetch(:workflow_run_id))
    workflow_run_attempt = validate_workflow_run_attempt!(input.fetch(:workflow_run_attempt))
    candidate_repository = validate_candidate_repository!(input.fetch(:candidate_repository, CANDIDATE_REPOSITORY))
    status = input.fetch(:status)
    fail_contract('invalid publication status') unless ALLOWED_STATUSES.include?(status)

    policy_decision = input.fetch(:policy_decision)
    fail_contract('policy decision must be PASS or FAIL') unless [PASS, FAIL].include?(policy_decision)

    manifest = {
      'schema_version' => PUBLICATION_SCHEMA_VERSION,
      'source' => {
        'repository' => SOURCE_REPOSITORY,
        'revision' => source_revision
      },
      'workflow' => {
        'run_id' => workflow_run_id,
        'run_attempt' => workflow_run_attempt
      },
      'target' => {
        'platform' => TARGET_PLATFORM
      },
      'registry' => {
        'host' => REGISTRY_HOST
      },
      'local' => {
        'state' => validate_local_state!(input.fetch(:local_state)),
        'image_id' => validate_local_image_id!(input.fetch(:local_image_id)),
        'archive_sha256' => validate_sha256_hex!(input.fetch(:local_archive_sha256))
      },
      'candidate' => candidate_manifest_for(input, source_revision, workflow_run_id, workflow_run_attempt, candidate_repository, status),
      'verification' => verification_manifest_for(input, status),
      'tools' => {
        'syft' => {
          'version' => normalize_version(input.fetch(:syft_version)),
          'expected_version' => normalize_version(versions.fetch('SYFT_VERSION'))
        },
        'grype' => {
          'version' => normalize_version(input.fetch(:grype_version)),
          'expected_version' => normalize_version(versions.fetch('GRYPE_VERSION'))
        }
      },
      'sbom' => {
        'cyclonedx' => evidence_file(input.fetch(:cyclonedx_filename), input.fetch(:cyclonedx_sha256)),
        'syft_json' => evidence_file(input.fetch(:syft_json_filename), input.fetch(:syft_json_sha256))
      },
      'vulnerability' => {
        'report' => evidence_file(input.fetch(:vulnerability_report_filename), input.fetch(:vulnerability_report_sha256)),
        'database' => validate_vulnerability_database!(input.fetch(:vulnerability_database)),
        'evidence_source' => validate_vulnerability_evidence_source!(input.fetch(:vulnerability_evidence_source), status),
        'policy_result' => evidence_file(input.fetch(:policy_result_filename), input.fetch(:policy_result_sha256)),
        'decision' => policy_decision
      },
      'publication' => {
        'status' => status
      }
    }

    if %w[published existing].include?(status)
      authoritative_repository = validate_authoritative_repository!(input.fetch(:authoritative_repository, AUTHORITATIVE_REPOSITORY))
      validate_repository_separation!(
        candidate_repository: candidate_repository,
        authoritative_repository: authoritative_repository
      )
      authoritative_digest = validate_digest!(input.fetch(:authoritative_digest))
      manifest['authoritative'] = {
        'repository' => authoritative_repository,
        'tag' => authoritative_tag(source_revision),
        'digest' => authoritative_digest
      }
    elsif input.key?(:authoritative_digest) || input.key?(:authoritative_tag) || input.key?(:authoritative_repository)
      fail_contract('candidate or local-blocked publication must not include authoritative fields')
    end

    validate_manifest_object!(manifest, versions_file: versions_file)
    manifest
  end

  def candidate_manifest_for(input, source_revision, workflow_run_id, workflow_run_attempt, candidate_repository, status)
    base = {
      'repository' => candidate_repository,
      'tag' => candidate_tag(source_revision, workflow_run_id, workflow_run_attempt),
      'role' => 'VERIFIED_PUBLIC_STAGING',
      'expected_visibility' => 'public'
    }

    return base.merge('published' => false) if %w[local_blocked existing].include?(status)

    base.merge(
      'published' => true,
      'digest' => validate_digest!(input.fetch(:candidate_digest))
    )
  end

  def verification_manifest_for(input, status)
    if status == 'local_blocked'
      {
        'scan_target_type' => 'LOCAL_ARCHIVE_SHA256',
        'scan_target_sha256' => validate_sha256_hex!(input.fetch(:local_archive_sha256))
      }
    else
      {
        'scan_target_type' => 'OCI_REGISTRY_DIGEST',
        'scan_target_digest' => validate_digest!(input.fetch(:scan_target_digest))
      }
    end
  end

  def write_manifest(path, manifest)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#{JSON.pretty_generate(manifest)}\n")
    File.write("#{path}.sha256", "#{sha256_file(path)}  #{File.basename(path)}\n")
  end

  def sidecar_valid?(path)
    sidecar = "#{path}.sha256"
    File.file?(sidecar) && File.read(sidecar).strip == "#{sha256_file(path)}  #{File.basename(path)}"
  end

  def validate_manifest_file!(path, versions_file:)
    fail_contract('publication evidence checksum sidecar mismatch') unless sidecar_valid?(path)

    validate_manifest_object!(read_json(path), versions_file: versions_file)
  end

  def validate_manifest_object!(manifest, versions_file:)
    fail_contract('publication evidence must be an object') unless manifest.is_a?(Hash)
    fail_contract('invalid publication schema') unless manifest['schema_version'] == PUBLICATION_SCHEMA_VERSION

    versions = read_versions(versions_file)
    source = manifest.fetch('source')
    workflow = manifest.fetch('workflow')
    registry = manifest.fetch('registry')
    local = manifest.fetch('local')
    candidate = manifest.fetch('candidate')
    verification = manifest.fetch('verification')
    tools = manifest.fetch('tools')
    sbom = manifest.fetch('sbom')
    vulnerability = manifest.fetch('vulnerability')
    publication = manifest.fetch('publication')
    status = publication.fetch('status')
    fail_contract('invalid publication status') unless ALLOWED_STATUSES.include?(status)

    source_revision = validate_source_revision!(source.fetch('revision'))
    fail_contract('source repository mismatch') unless source.fetch('repository') == SOURCE_REPOSITORY
    workflow_run_id = validate_workflow_run_id!(workflow.fetch('run_id'))
    workflow_run_attempt = validate_workflow_run_attempt!(workflow.fetch('run_attempt'))
    fail_contract('target platform mismatch') unless manifest.fetch('target').fetch('platform') == TARGET_PLATFORM
    fail_contract('registry host mismatch') unless registry.fetch('host') == REGISTRY_HOST
    fail_contract('registry repository is ambiguous; use candidate.repository and authoritative.repository') if registry.key?('repository')

    candidate_repository = validate_candidate_repository!(candidate.fetch('repository'))
    fail_contract('candidate tag mismatch') unless candidate.fetch('tag') == candidate_tag(
      source_revision,
      workflow_run_id,
      workflow_run_attempt
    )

    local_state = validate_local_state!(local.fetch('state'))
    validate_local_image_id!(local.fetch('image_id'))
    local_archive_sha256 = validate_sha256_hex!(local.fetch('archive_sha256'))
    fail_contract('candidate must declare verified public staging role') unless candidate.fetch('role') == 'VERIFIED_PUBLIC_STAGING'
    fail_contract('candidate expected visibility must be public') unless candidate.fetch('expected_visibility') == 'public'

    fail_contract('Syft version does not match pin') unless normalize_version(tools.fetch('syft').fetch('version')) == normalize_version(versions.fetch('SYFT_VERSION'))
    fail_contract('Grype version does not match pin') unless normalize_version(tools.fetch('grype').fetch('version')) == normalize_version(versions.fetch('GRYPE_VERSION'))
    fail_contract('Syft expected version does not match pin') unless normalize_version(tools.fetch('syft').fetch('expected_version')) == normalize_version(versions.fetch('SYFT_VERSION'))
    fail_contract('Grype expected version does not match pin') unless normalize_version(tools.fetch('grype').fetch('expected_version')) == normalize_version(versions.fetch('GRYPE_VERSION'))

    %w[cyclonedx syft_json].each do |key|
      validate_sha256_hex!(sbom.fetch(key).fetch('sha256'))
      fail_contract("#{key} filename missing") if sbom.fetch(key).fetch('filename').to_s.empty?
    end
    validate_sha256_hex!(vulnerability.fetch('report').fetch('sha256'))
    validate_sha256_hex!(vulnerability.fetch('policy_result').fetch('sha256'))
    validate_vulnerability_database!(vulnerability.fetch('database'))
    validate_vulnerability_evidence_source!(vulnerability.fetch('evidence_source'), status)

    decision = vulnerability.fetch('decision')
    fail_contract('policy decision must be PASS or FAIL') unless [PASS, FAIL].include?(decision)

    case status
    when 'local_blocked'
      fail_contract('candidate state must not include authoritative fields') if manifest.key?('authoritative')
      fail_contract('local blocked state must not publish candidate digest') if candidate.key?('digest')
      fail_contract('local blocked state must mark candidate unpublished') unless candidate.fetch('published') == false
      fail_contract('local blocked state requires LOCAL_BLOCKED') unless local_state == 'LOCAL_BLOCKED'
      fail_contract('local blocked scan target mismatch') unless verification.fetch('scan_target_type') == 'LOCAL_ARCHIVE_SHA256'
      fail_contract('local blocked scan target must match local archive') unless verification.fetch('scan_target_sha256') == local_archive_sha256
      fail_contract('local blocked state requires policy FAIL') unless decision == FAIL
    when 'candidate'
      fail_contract('candidate state must not include authoritative fields') if manifest.key?('authoritative')
      fail_contract('candidate state requires policy PASS') unless decision == PASS
      fail_contract('candidate state requires LOCAL_VERIFIED') unless local_state == 'LOCAL_VERIFIED'
      fail_contract('candidate state must mark candidate published') unless candidate.fetch('published') == true
      candidate_digest = validate_digest!(candidate.fetch('digest'))
      scan_digest = validate_digest!(verification.fetch('scan_target_digest'))
      fail_contract('candidate scan target must be registry digest') unless verification.fetch('scan_target_type') == 'OCI_REGISTRY_DIGEST'
      validate_candidate_continuity!(
        candidate_registry_digest: candidate_digest,
        verified_scan_target_digest: scan_digest
      )
    when 'published'
      fail_contract('published state requires policy PASS') unless decision == PASS
      fail_contract('published state requires LOCAL_VERIFIED') unless local_state == 'LOCAL_VERIFIED'
      fail_contract('published state must mark candidate published') unless candidate.fetch('published') == true
      candidate_digest = validate_digest!(candidate.fetch('digest'))
      scan_digest = validate_digest!(verification.fetch('scan_target_digest'))
      fail_contract('published scan target must be registry digest') unless verification.fetch('scan_target_type') == 'OCI_REGISTRY_DIGEST'
      authoritative = manifest.fetch('authoritative')
      authoritative_repository = validate_authoritative_repository!(authoritative.fetch('repository'))
      validate_repository_separation!(
        candidate_repository: candidate_repository,
        authoritative_repository: authoritative_repository
      )
      fail_contract('authoritative tag mismatch') unless authoritative.fetch('tag') == authoritative_tag(source_revision)
      authoritative_digest = validate_digest!(authoritative.fetch('digest'))
      validate_complete_continuity!(
        candidate_registry_digest: candidate_digest,
        verified_scan_target_digest: scan_digest,
        authoritative_tag_digest: authoritative_digest,
        handoff_digest: authoritative_digest
      )
    when 'existing'
      fail_contract('existing state requires policy PASS') unless decision == PASS
      fail_contract('existing state requires EXISTING_PUBLICATION') unless local_state == 'EXISTING_PUBLICATION'
      fail_contract('existing state must not publish a candidate') unless candidate.fetch('published') == false
      fail_contract('existing state must not include candidate digest') if candidate.key?('digest')
      fail_contract('existing scan target must be registry digest') unless verification.fetch('scan_target_type') == 'OCI_REGISTRY_DIGEST'
      scan_digest = validate_digest!(verification.fetch('scan_target_digest'))
      authoritative = manifest.fetch('authoritative')
      authoritative_repository = validate_authoritative_repository!(authoritative.fetch('repository'))
      validate_repository_separation!(
        candidate_repository: candidate_repository,
        authoritative_repository: authoritative_repository
      )
      fail_contract('authoritative tag mismatch') unless authoritative.fetch('tag') == authoritative_tag(source_revision)
      authoritative_digest = validate_digest!(authoritative.fetch('digest'))
      validate_complete_continuity!(
        candidate_registry_digest: scan_digest,
        verified_scan_target_digest: scan_digest,
        authoritative_tag_digest: authoritative_digest,
        handoff_digest: authoritative_digest
      )
    end

    manifest
  rescue KeyError => e
    fail_contract("publication evidence missing required field: #{e.message}")
  end

  def build_handoff(manifest, evidence_sha256)
    validate_manifest_object!(manifest, versions_file: File.join(Dir.pwd, 'scripts/supply-chain/versions.env'))
    status = manifest.fetch('publication').fetch('status')
    fail_contract('handoff requires successful publication evidence') unless %w[published existing].include?(status)

    digest = validate_digest!(manifest.fetch('authoritative').fetch('digest'))
    {
      'apiVersion' => HANDOFF_API_VERSION,
      'kind' => HANDOFF_KIND,
      'image' => {
        'repository' => AUTHORITATIVE_REPOSITORY,
        'digest' => digest
      },
      'source' => {
        'revision' => manifest.fetch('source').fetch('revision')
      },
      'publicationEvidence' => {
        'file' => PUBLICATION_MANIFEST,
        'sha256' => validate_sha256_hex!(evidence_sha256)
      }
    }
  end

  def validate_handoff_object!(handoff, manifest)
    validate_manifest_object!(manifest, versions_file: File.join(Dir.pwd, 'scripts/supply-chain/versions.env'))
    status = manifest.fetch('publication').fetch('status')
    fail_contract('handoff requires successful publication evidence') unless %w[published existing].include?(status)

    fail_contract('invalid handoff apiVersion') unless handoff.fetch('apiVersion') == HANDOFF_API_VERSION
    fail_contract('invalid handoff kind') unless handoff.fetch('kind') == HANDOFF_KIND
    fail_contract('handoff repository mismatch') unless handoff.fetch('image').fetch('repository') == AUTHORITATIVE_REPOSITORY
    digest = validate_digest!(handoff.fetch('image').fetch('digest'))
    fail_contract('handoff digest mismatch') unless digest == manifest.fetch('authoritative').fetch('digest')
    fail_contract('handoff source revision mismatch') unless handoff.fetch('source').fetch('revision') == manifest.fetch('source').fetch('revision')
    fail_contract('handoff evidence file mismatch') unless handoff.fetch('publicationEvidence').fetch('file') == PUBLICATION_MANIFEST
    validate_sha256_hex!(handoff.fetch('publicationEvidence').fetch('sha256'))

    handoff
  rescue KeyError => e
    fail_contract("handoff missing required field: #{e.message}")
  end
end
