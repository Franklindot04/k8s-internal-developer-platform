#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require 'yaml'

require_relative 'publication'

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

  def publication_contract
    @publication_contract ||= File.read('scripts/supply-chain/publication.rb')
  end

  def run_bash(script)
    Open3.capture3('bash', '-c', script)
  end

  def repo_root
    @repo_root ||= File.expand_path('../..', __dir__)
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
    assert_includes(runtime, 'classify_authoritative_manifest_state')
    assert_includes(runtime, 'registry_manifest_get')
    assert_includes(runtime, 'registry_bearer_token')
    assert_includes(runtime, 'classify_registry_token_response')
    assert_includes(runtime, 'classify_registry_manifest_response')
    assert_includes(runtime, 'emit_precheck_telemetry')
    assert_includes(runtime, 'pre_promotion_recheck_state')
    refute_includes(runtime, '/users/Franklindot04/packages?package_type=container')
    refute_includes(runtime, 'GITHUB_PACKAGES_API_ROOT')
    assert_includes(runtime, 'LOCAL_POLICY_DECISION')
    assert_includes(runtime, 'docker push "$candidate_ref"')
  end

  def test_registry_manifest_precheck_fails_closed_with_safe_telemetry
    assert_includes(runtime, 'precheck_stage=%s http_status=%s registry_error_code=%s classification=%s')
    assert_includes(runtime, 'next_stage=local-quarantine')
    assert_includes(runtime, 'AUTHORITATIVE_STATE_CLASSIFICATION')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_NETWORK_FAILURE')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_AUTH_FAILURE')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_MALFORMED')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_ABSENT')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_UNOBSERVABLE')
    assert_includes(runtime, 'repository:$AUTHORITATIVE_REGISTRY_PATH:pull')
    assert_includes(publication_contract, 'MANIFEST_UNKNOWN')
    assert_includes(publication_contract, 'NAME_UNKNOWN')
    assert_includes(runtime, 'authoritative pre-build check failed closed')
    assert_includes(runtime, 'authoritative pre-promotion recheck failed closed')
    refute_includes(runtime, 'return 5')
    refute_match(/printf .*Authorization|printf .*Bearer|cat "\$token_body"|cat "\$manifest_body"/, runtime)
  end

  def test_live_unobservable_token_regression_routes_nonfatally
    result = SupplyChainPublication.classify_registry_token_response(
      http_status: '403',
      body: JSON.generate('errors' => [{ 'code' => 'DENIED' }]),
      mode: 'anonymous'
    )

    assert_equal(SupplyChainPublication::PUBLIC_AUTHORITATIVE_UNOBSERVABLE, result.fetch('classification'))
    assert_equal('DENIED', result.fetch('registry_error_code'))
    assert_includes(runtime, 'AUTHORITATIVE_STATE_CLASSIFICATION="$REGISTRY_TOKEN_CLASSIFICATION"')
    assert_includes(runtime, 'PUBLIC_AUTHORITATIVE_UNOBSERVABLE)')
    assert_includes(runtime, 'next_stage=local-quarantine')
  end

  def test_recognized_public_states_are_nonfatal_under_errexit
    script = <<~'BASH'
      set -Eeuo pipefail
      route_state() {
        AUTHORITATIVE_STATE_CLASSIFICATION="$1"
        return 0
      }
      candidate_precheck() {
        local precheck_status=0
        set +e
        route_state "$1"
        precheck_status="$?"
        set -e
        [ "$precheck_status" -eq 0 ] || return 1
        case "$AUTHORITATIVE_STATE_CLASSIFICATION" in
          PUBLIC_AUTHORITATIVE_EXISTS) printf 'next_stage=existing-publication\n' ;;
          PUBLIC_AUTHORITATIVE_ABSENT|PUBLIC_AUTHORITATIVE_UNOBSERVABLE) printf 'next_stage=local-quarantine\n' ;;
          *) return 1 ;;
        esac
      }
      candidate_precheck PUBLIC_AUTHORITATIVE_EXISTS
      candidate_precheck PUBLIC_AUTHORITATIVE_ABSENT
      candidate_precheck PUBLIC_AUTHORITATIVE_UNOBSERVABLE
    BASH

    stdout, stderr, status = run_bash(script)

    assert(status.success?, stderr)
    assert_equal(
      "next_stage=existing-publication\nnext_stage=local-quarantine\nnext_stage=local-quarantine\n",
      stdout
    )
  end

  def test_failure_states_remain_fatal_under_errexit
    script = <<~'BASH'
      set -Eeuo pipefail
      fail_state() {
        AUTHORITATIVE_STATE_CLASSIFICATION="PUBLIC_AUTHORITATIVE_DENIED"
        return 1
      }
      candidate_precheck() {
        local precheck_status=0
        set +e
        fail_state
        precheck_status="$?"
        set -e
        [ "$precheck_status" -eq 0 ] || return 1
        printf 'unexpected-success\n'
      }
      candidate_precheck
    BASH

    stdout, _stderr, status = run_bash(script)

    refute(status.success?)
    assert_equal('', stdout)
  end

  def test_public_unobservable_ordering_remains_quarantine_then_policy_then_authenticated_check_then_push
    script = <<~'BASH'
      set -Eeuo pipefail
      classify_public_state() {
        AUTHORITATIVE_STATE_CLASSIFICATION="PUBLIC_AUTHORITATIVE_UNOBSERVABLE"
        return 0
      }
      run_candidate() {
        printf 'LOCAL_BUILD\n'
        printf 'LOCAL_POLICY_PASS\n'
        printf 'AUTHENTICATED_SOURCE_CHECK\n'
        printf 'CANDIDATE_PUSH\n'
      }
      candidate_precheck() {
        local precheck_status=0
        set +e
        classify_public_state
        precheck_status="$?"
        set -e
        [ "$precheck_status" -eq 0 ] || return 1
        case "$AUTHORITATIVE_STATE_CLASSIFICATION" in
          PUBLIC_AUTHORITATIVE_UNOBSERVABLE)
            printf 'PUBLIC_UNOBSERVABLE\n'
            run_candidate
            ;;
          *) return 1 ;;
        esac
      }
      candidate_precheck
    BASH

    stdout, stderr, status = run_bash(script)

    assert(status.success?, stderr)
    assert_equal(
      "PUBLIC_UNOBSERVABLE\nLOCAL_BUILD\nLOCAL_POLICY_PASS\nAUTHENTICATED_SOURCE_CHECK\nCANDIDATE_PUSH\n",
      stdout
    )
  end

  def test_vulnerability_evaluator_is_repo_anchored_for_quarantine_cwd
    assert_includes(runtime, 'REPO_ROOT=')
    assert_includes(runtime, 'repo_path scripts/supply-chain/evaluate-vulnerabilities.rb')
    refute_includes(runtime, 'ruby scripts/supply-chain/evaluate-vulnerabilities.rb')

    Dir.mktmpdir do |dir|
      report = File.join(repo_root, 'tests/fixtures/supply-chain-policy/no-findings.json')
      output = File.join(dir, 'local-policy-result.json')
      helper = File.join(repo_root, 'scripts/supply-chain/evaluate-vulnerabilities.rb')
      stdout, stderr, status = Open3.capture3('ruby', helper, report, output, chdir: dir)

      assert(status.success?, stderr)
      assert_includes(stdout, '[ok] vulnerability policy decision: PASS')
      assert(File.file?(output), 'policy output should remain in the quarantine workspace')
      refute(File.exist?(File.join(repo_root, 'local-policy-result.json')))
    end
  end

  def test_cwd_relative_evaluator_path_reproduces_live_failure
    Dir.mktmpdir do |dir|
      _stdout, stderr, status = Open3.capture3('ruby', 'scripts/supply-chain/evaluate-vulnerabilities.rb', chdir: dir)

      refute(status.success?)
      assert_includes(stderr, 'No such file or directory')
      assert_includes(stderr, 'scripts/supply-chain/evaluate-vulnerabilities.rb')
    end
  end

  def test_missing_anchored_evaluator_fails_closed
    Dir.mktmpdir do |dir|
      missing_helper = File.join(dir, 'missing-evaluate-vulnerabilities.rb')
      report = File.join(repo_root, 'tests/fixtures/supply-chain-policy/no-findings.json')
      output = File.join(dir, 'local-policy-result.json')
      _stdout, stderr, status = Open3.capture3('ruby', missing_helper, report, output, chdir: dir)

      refute(status.success?)
      assert_includes(stderr, 'No such file or directory')
      refute(File.exist?(output))
    end
  end

  def test_evaluator_argument_order_is_preserved
    assert_match(
      %r{ruby "\$\(repo_path scripts/supply-chain/evaluate-vulnerabilities\.rb\)" "\$WORK_DIR/\$\{prefix\}-vulnerabilities\.json" "\$policy_result"},
      runtime
    )
  end

  def policy_result_handoff_script(scenario)
    <<~BASH
      set -Eeuo pipefail
      WORK_DIR="$(mktemp -d)"
      SCENARIO="#{scenario}"

      policy_result_decision() {
        ruby -rjson -e '
          path = ARGV.fetch(0)
          abort("[error] missing") unless File.file?(path)
          abort("[error] empty") if File.zero?(path)
          result = JSON.parse(File.read(path))
          abort("[error] object") unless result.is_a?(Hash)
          decision = result.fetch("decision")
          abort("[error] type") unless decision.is_a?(String)
          abort("[error] value") unless %w[PASS FAIL].include?(decision)
          puts decision
        ' "$1"
      }

      generate_sbom_and_vulnerability() {
        local result="$WORK_DIR/local-policy-result.json"
        rm -f "$result"
        case "$SCENARIO" in
          pass) printf '{"decision":"PASS"}\\n' >"$result" ;;
          fail) printf '{"decision":"FAIL"}\\n' >"$result" ;;
          missing) : ;;
          malformed) printf '{not-json\\n' >"$result" ;;
          unknown) printf '{"decision":"UNKNOWN"}\\n' >"$result" ;;
          stale)
            printf '[error] evaluator failed\\n' >&2
            return 1
            ;;
          *) return 2 ;;
        esac
      }

      authenticated_source_check() {
        printf 'AUTHENTICATED_SOURCE_CHECK\\n'
      }

      candidate_push() {
        printf 'CANDIDATE_PUSH\\n'
      }

      run_candidate() {
        if [ "$SCENARIO" = "stale" ]; then
          printf '{"decision":"PASS"}\\n' >"$WORK_DIR/local-policy-result.json"
        fi
        (cd "$WORK_DIR" && generate_sbom_and_vulnerability)
        LOCAL_POLICY_DECISION="$(policy_result_decision "$WORK_DIR/local-policy-result.json")"
        printf 'LOCAL_POLICY_RESULT=%s\\n' "$LOCAL_POLICY_DECISION"
        if [ "$LOCAL_POLICY_DECISION" = "FAIL" ]; then
          printf 'FAIL_CLOSED\\n'
          return 1
        fi
        [ "$LOCAL_POLICY_DECISION" = "PASS" ] || return 1
        authenticated_source_check
        candidate_push
      }

      run_candidate
    BASH
  end

  def test_policy_result_handoff_reproduces_live_failure_without_unbound_variable
    stdout, stderr, status = run_bash(policy_result_handoff_script('pass'))

    assert(status.success?, stderr)
    assert_includes(stdout, "LOCAL_POLICY_RESULT=PASS\n")
    assert_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    assert_includes(stdout, "CANDIDATE_PUSH\n")
    refute_includes(stderr, 'unbound variable')
  end

  def test_fail_policy_result_fails_closed_before_authentication
    stdout, _stderr, status = run_bash(policy_result_handoff_script('fail'))

    refute(status.success?)
    assert_includes(stdout, "LOCAL_POLICY_RESULT=FAIL\n")
    assert_includes(stdout, "FAIL_CLOSED\n")
    refute_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    refute_includes(stdout, "CANDIDATE_PUSH\n")
  end

  def test_missing_policy_result_fails_closed
    stdout, _stderr, status = run_bash(policy_result_handoff_script('missing'))

    refute(status.success?)
    refute_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    refute_includes(stdout, "CANDIDATE_PUSH\n")
  end

  def test_malformed_policy_result_fails_closed
    stdout, _stderr, status = run_bash(policy_result_handoff_script('malformed'))

    refute(status.success?)
    refute_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    refute_includes(stdout, "CANDIDATE_PUSH\n")
  end

  def test_unknown_policy_result_fails_closed
    stdout, _stderr, status = run_bash(policy_result_handoff_script('unknown'))

    refute(status.success?)
    refute_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    refute_includes(stdout, "CANDIDATE_PUSH\n")
  end

  def test_stale_pass_policy_result_is_removed_before_generation
    stdout, stderr, status = run_bash(policy_result_handoff_script('stale'))

    refute(status.success?)
    assert_includes(stderr, '[error] evaluator failed')
    refute_includes(stdout, "LOCAL_POLICY_RESULT=PASS\n")
    refute_includes(stdout, "AUTHENTICATED_SOURCE_CHECK\n")
    refute_includes(stdout, "CANDIDATE_PUSH\n")
  end

  def test_candidate_push_is_after_local_policy_without_pre_candidate_authoritative_check
    local_policy_index = runtime.index('LOCAL_POLICY_DECISION="$(policy_result_decision "$WORK_DIR/local-policy-result.json")"')
    local_policy_pass_index = runtime.index('[ "$LOCAL_POLICY_DECISION" = "PASS" ] || fail "local vulnerability policy did not pass"')
    candidate_push_index = runtime.index('docker push "$candidate_ref"')

    refute_nil(local_policy_index)
    refute_nil(local_policy_pass_index)
    refute_nil(candidate_push_index)
    assert_operator(local_policy_index, :<, local_policy_pass_index)
    assert_operator(local_policy_pass_index, :<, candidate_push_index)
    refute_includes(runtime, 'authenticated-source-check')
    refute_includes(runtime, 'authenticated authoritative source tag exists before candidate publication')
    refute_includes(runtime, 'authenticated authoritative source check failed closed')
  end

  def test_live_candidate_evidence_failure_reproduces_unexported_source_revision
    script = <<~'BASH'
      set -Eeuo pipefail
      SOURCE_REVISION=59a76860307bb46a135de5794b7380b0e11df59a
      WORKFLOW_RUN_ID=32434344588
      WORKFLOW_RUN_ATTEMPT=1
      ruby -e 'ENV.fetch("SOURCE_REVISION")'
    BASH

    _stdout, stderr, status = run_bash(script)

    refute(status.success?)
    assert_includes(stderr, 'key not found: "SOURCE_REVISION"')
  end

  def test_candidate_evidence_metadata_is_passed_explicitly_to_child_process
    script = <<~'BASH'
      set -Eeuo pipefail
      SOURCE_REVISION=59a76860307bb46a135de5794b7380b0e11df59a
      WORKFLOW_RUN_ID=32434344588
      WORKFLOW_RUN_ATTEMPT=1
      SOURCE_REVISION="$SOURCE_REVISION" \
        WORKFLOW_RUN_ID="$WORKFLOW_RUN_ID" \
        WORKFLOW_RUN_ATTEMPT="$WORKFLOW_RUN_ATTEMPT" \
        ruby -e 'puts [ENV.fetch("SOURCE_REVISION"), ENV.fetch("WORKFLOW_RUN_ID"), ENV.fetch("WORKFLOW_RUN_ATTEMPT")].join(":")'
    BASH

    stdout, stderr, status = run_bash(script)

    assert(status.success?, stderr)
    assert_equal("59a76860307bb46a135de5794b7380b0e11df59a:32434344588:1\n", stdout)
  end

  def test_candidate_evidence_metadata_validation_and_explicit_environment_contract
    evidence_start = runtime.index('build_publication_evidence()')
    evidence_body = runtime[evidence_start..]
    validate_index = evidence_body.index('validate_evidence_metadata "$status" "$authoritative_digest"')
    ruby_index = evidence_body.index('ruby -r ./scripts/supply-chain/publication.rb -e')

    refute_nil(evidence_start)
    refute_nil(validate_index)
    refute_nil(ruby_index)
    assert_operator(validate_index, :<, ruby_index)
    assert_includes(runtime, 'SOURCE_REVISION="$SOURCE_REVISION" \\')
    assert_includes(runtime, 'WORKFLOW_RUN_ID="$WORKFLOW_RUN_ID" \\')
    assert_includes(runtime, 'WORKFLOW_RUN_ATTEMPT="$WORKFLOW_RUN_ATTEMPT" \\')
    assert_includes(runtime, 'LOCAL_IMAGE_ID="$LOCAL_IMAGE_ID" \\')
    assert_includes(runtime, 'LOCAL_ARCHIVE_SHA256="$LOCAL_ARCHIVE_SHA256" \\')
    assert_includes(runtime, 'CANDIDATE_REGISTRY_DIGEST="${CANDIDATE_REGISTRY_DIGEST:-}" \\')
    assert_includes(runtime, 'VERIFIED_SCAN_TARGET_DIGEST="${VERIFIED_SCAN_TARGET_DIGEST:-}" \\')
    assert_includes(runtime, 'POLICY_DECISION="$POLICY_DECISION" \\')
    assert_includes(runtime, '[ "$(git rev-parse HEAD)" = "$SOURCE_REVISION" ] || fail_evidence_metadata "source_revision"')
    assert_includes(runtime, '[ "$CANDIDATE_REGISTRY_DIGEST" = "$VERIFIED_SCAN_TARGET_DIGEST" ] || fail_evidence_metadata "scan_target_digest"')
  end

  def test_public_unobservable_local_policy_pass_is_candidate_eligible_not_authoritative_eligible
    script = <<~'BASH'
      set -Eeuo pipefail
      authoritative_eligible=false
      candidate_push() { printf 'CANDIDATE_PUSH_ELIGIBLE\n'; }
      authoritative_mutation() { authoritative_eligible=true; printf 'AUTHORITATIVE_MUTATION\n'; }
      run_candidate() {
        AUTHORITATIVE_STATE_CLASSIFICATION="PUBLIC_AUTHORITATIVE_UNOBSERVABLE"
        LOCAL_POLICY_DECISION="PASS"
        [ "$LOCAL_POLICY_DECISION" = "PASS" ] || return 1
        candidate_push
      }
      run_candidate
      [ "$authoritative_eligible" = "false" ]
    BASH

    stdout, stderr, status = run_bash(script)

    assert(status.success?, stderr)
    assert_equal("CANDIDATE_PUSH_ELIGIBLE\n", stdout)
  end

  def test_public_unobservable_local_policy_fail_blocks_candidate_and_authoritative
    script = <<~'BASH'
      set -Eeuo pipefail
      candidate_push() { printf 'CANDIDATE_PUSH\n'; }
      authoritative_mutation() { printf 'AUTHORITATIVE_MUTATION\n'; }
      run_candidate() {
        AUTHORITATIVE_STATE_CLASSIFICATION="PUBLIC_AUTHORITATIVE_UNOBSERVABLE"
        LOCAL_POLICY_DECISION="FAIL"
        [ "$LOCAL_POLICY_DECISION" = "PASS" ] || return 1
        candidate_push
      }
      run_candidate
    BASH

    stdout, _stderr, status = run_bash(script)

    refute(status.success?)
    refute_includes(stdout, "CANDIDATE_PUSH\n")
    refute_includes(stdout, "AUTHORITATIVE_MUTATION\n")
  end

  def test_candidate_job_has_no_authoritative_mutation_before_environment_job
    candidate_index = runtime.index('run_candidate()')
    authoritative_index = runtime.index('run_authoritative()')
    candidate_body = runtime[candidate_index...authoritative_index]

    assert_includes(candidate_body, 'docker push "$candidate_ref"')
    refute_includes(candidate_body, 'docker buildx imagetools create')
    refute_includes(candidate_body, '--tag "$AUTHORITATIVE_REPOSITORY:$AUTHORITATIVE_TAG"')
    refute_includes(candidate_body, 'image-reference.json')
  end

  def test_authoritative_recheck_is_before_mutation
    recheck_index = runtime.index('classify_authoritative_manifest_state "authenticated" "authoritative-recheck"')
    mutation_index = runtime.index('docker buildx imagetools create')

    refute_nil(recheck_index)
    refute_nil(mutation_index)
    assert_operator(recheck_index, :<, mutation_index)
    assert_includes(runtime, 'PRE_PROMOTION_EXISTS_SAME_DIGEST')
    assert_includes(runtime, 'PRE_PROMOTION_EXISTS_DIFFERENT_DIGEST')
  end

  def test_authoritative_reuses_candidate_scanner_metadata_without_local_db_status
    authoritative_index = runtime.index('run_authoritative()')
    initialize_index = runtime.index('initialize()')
    authoritative_body = runtime[authoritative_index...initialize_index]

    assert_includes(runtime, 'reuse_candidate_scanner_metadata()')
    assert_includes(authoritative_body, 'reuse_candidate_scanner_metadata "$candidate_evidence"')
    refute_includes(authoritative_body, 'record_tool_versions')
    assert_includes(runtime, '[ "$VULNERABILITY_EVIDENCE_SOURCE" = "VERIFIED_CANDIDATE_POST_PUSH" ]')
    assert_includes(runtime, 'grype db status -o json')
  end

  def test_authoritative_metadata_reuse_follows_digest_and_anonymous_verification
    authoritative_index = runtime.index('run_authoritative()')
    initialize_index = runtime.index('initialize()')
    authoritative_body = runtime[authoritative_index...initialize_index]
    digest_equality_index = authoritative_body.rindex('[ "$AUTHORITATIVE_TAG_DIGEST" = "$CANDIDATE_REGISTRY_DIGEST" ]')
    anonymous_index = authoritative_body.rindex('anonymous_pull_by_digest "$AUTHORITATIVE_REPOSITORY@$AUTHORITATIVE_TAG_DIGEST"')
    reuse_index = authoritative_body.rindex('reuse_candidate_scanner_metadata "$candidate_evidence"')
    evidence_index = authoritative_body.rindex('build_publication_evidence "published"')

    refute_nil(digest_equality_index)
    refute_nil(anonymous_index)
    refute_nil(reuse_index)
    refute_nil(evidence_index)
    assert_operator(digest_equality_index, :<, anonymous_index)
    assert_operator(anonymous_index, :<, reuse_index)
    assert_operator(reuse_index, :<, evidence_index)
  end

  def test_authoritative_metadata_reuse_fails_closed_for_digest_mismatch
    script = <<~'BASH'
      set -Eeuo pipefail
      validate_digest() { case "$1" in sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb) return 0 ;; *) return 1 ;; esac; }
      fail() { printf '[error] %s\n' "$1" >&2; exit 1; }
      CANDIDATE_REGISTRY_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      candidate_evidence="$(mktemp)"
      cat >"$candidate_evidence" <<'JSON'
      {
        "tools": {"syft": {"version": "1.51.0"}, "grype": {"version": "0.117.0"}},
        "vulnerability": {"database": "2026-08-20T06:17:08Z", "evidence_source": "VERIFIED_CANDIDATE_POST_PUSH"},
        "verification": {"scan_target_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
      }
      JSON
      reuse_candidate_scanner_metadata() {
        local candidate_evidence="$1"
        SYFT_VERSION_ACTUAL="$(jq -er '.tools.syft.version' "$candidate_evidence")" || fail "candidate evidence Syft version missing"
        GRYPE_VERSION_ACTUAL="$(jq -er '.tools.grype.version' "$candidate_evidence")" || fail "candidate evidence Grype version missing"
        VULNERABILITY_DATABASE="$(jq -er '.vulnerability.database' "$candidate_evidence")" || fail "candidate evidence vulnerability database metadata missing"
        VERIFIED_SCAN_TARGET_DIGEST="$(jq -er '.verification.scan_target_digest' "$candidate_evidence")" || fail "candidate evidence scan target digest missing"
        VULNERABILITY_EVIDENCE_SOURCE="$(jq -er '.vulnerability.evidence_source' "$candidate_evidence")" || fail "candidate evidence vulnerability source missing"
        validate_digest "$VERIFIED_SCAN_TARGET_DIGEST"
        [ "$VERIFIED_SCAN_TARGET_DIGEST" = "$CANDIDATE_REGISTRY_DIGEST" ] || fail "candidate scan target digest differs from candidate digest"
        [ "$VULNERABILITY_EVIDENCE_SOURCE" = "VERIFIED_CANDIDATE_POST_PUSH" ] || fail "candidate vulnerability evidence source is not reusable"
      }
      reuse_candidate_scanner_metadata "$candidate_evidence"
    BASH

    _stdout, stderr, status = run_bash(script)

    refute(status.success?)
    assert_includes(stderr, 'candidate scan target digest differs from candidate digest')
  end

  def test_authoritative_metadata_reuse_fails_closed_for_missing_database
    script = <<~'BASH'
      set -Eeuo pipefail
      fail() { printf '[error] %s\n' "$1" >&2; exit 1; }
      CANDIDATE_REGISTRY_DIGEST="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      candidate_evidence="$(mktemp)"
      cat >"$candidate_evidence" <<'JSON'
      {
        "tools": {"syft": {"version": "1.51.0"}, "grype": {"version": "0.117.0"}},
        "vulnerability": {"evidence_source": "VERIFIED_CANDIDATE_POST_PUSH"},
        "verification": {"scan_target_digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
      }
      JSON
      reuse_candidate_scanner_metadata() {
        local candidate_evidence="$1"
        VULNERABILITY_DATABASE="$(jq -er '.vulnerability.database' "$candidate_evidence")" || fail "candidate evidence vulnerability database metadata missing"
      }
      reuse_candidate_scanner_metadata "$candidate_evidence"
    BASH

    _stdout, stderr, status = run_bash(script)

    refute(status.success?)
    assert_includes(stderr, 'candidate evidence vulnerability database metadata missing')
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
