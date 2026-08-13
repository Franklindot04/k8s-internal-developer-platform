#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

POLICY_VERSION = 'stage-6c1-v1'
BLOCKING_SEVERITIES = ['critical'].freeze
KNOWN_SEVERITIES = %w[critical high medium low negligible unknown].freeze

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

def normalize_severity(value)
  severity = value.to_s.strip.downcase
  severity.empty? ? 'unknown' : severity
end

def load_report(path)
  fail_with("vulnerability report missing: #{path}") unless path && File.file?(path)

  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  fail_with("malformed vulnerability report: #{e.message}")
end

def finding_severity(match)
  vulnerability = match.fetch('vulnerability') { {} }
  normalize_severity(vulnerability['severity'])
end

def evaluate(report)
  matches = report.fetch('matches') do
    fail_with('vulnerability report is missing matches array')
  end
  fail_with('vulnerability report matches field is not an array') unless matches.is_a?(Array)

  counts = Hash.new(0)
  KNOWN_SEVERITIES.each { |severity| counts[severity] = 0 }

  matches.each do |match|
    fail_with('vulnerability report match is not an object') unless match.is_a?(Hash)

    severity = finding_severity(match)
    severity = 'unknown' unless KNOWN_SEVERITIES.include?(severity)
    counts[severity] += 1
  end

  blocking_count = BLOCKING_SEVERITIES.sum { |severity| counts.fetch(severity, 0) }
  {
    'policy_version' => POLICY_VERSION,
    'blocking_severities' => BLOCKING_SEVERITIES.map(&:upcase),
    'counts_by_severity' => counts.transform_keys(&:upcase),
    'blocking_finding_count' => blocking_count,
    'decision' => blocking_count.positive? ? 'FAIL' : 'PASS'
  }
end

def write_json(path, object)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, "#{JSON.pretty_generate(object)}\n")
end

def run(report_path, output_path)
  report = load_report(report_path)
  result = evaluate(report)
  write_json(output_path, result)
  puts "[ok] vulnerability policy decision: #{result['decision']}"
  exit(result['decision'] == 'PASS' ? 0 : 1)
end

def expect_fixture(name, path, expected)
  output = File.join(Dir.mktmpdir, "#{name}.json")
  report = load_report(path)
  result = evaluate(report)
  write_json(output, result)
  actual = result['decision']
  fail_with("#{name}: expected #{expected}, got #{actual}") unless actual == expected
end

def expect_failure(name)
  yield
  fail_with("#{name}: expected failure")
rescue SystemExit => e
  raise if e.status.zero?
end

def self_test(fixture_dir)
  require 'tmpdir'

  expect_fixture('no findings', File.join(fixture_dir, 'no-findings.json'), 'PASS')
  expect_fixture('high only', File.join(fixture_dir, 'high-only.json'), 'PASS')
  expect_fixture('critical', File.join(fixture_dir, 'critical.json'), 'FAIL')
  expect_fixture('critical unfixed', File.join(fixture_dir, 'critical-unfixed.json'), 'FAIL')
  expect_fixture('unknown only', File.join(fixture_dir, 'unknown-only.json'), 'PASS')
  expect_failure('malformed json') { load_report(File.join(fixture_dir, 'malformed.json')) }
  expect_failure('missing report') { load_report(File.join(fixture_dir, 'missing.json')) }
  puts '[ok] vulnerability policy synthetic tests passed'
end

if __FILE__ == $PROGRAM_NAME
  case ARGV[0]
  when '--self-test'
    self_test(ARGV[1] || 'tests/fixtures/supply-chain-policy')
  else
    fail_with('usage: evaluate-vulnerabilities.rb <report.json> <policy-result.json>') unless ARGV.length == 2
    run(ARGV[0], ARGV[1])
  end
end
