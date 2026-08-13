#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'optparse'
require 'fileutils'
require_relative 'evaluate-vulnerabilities'

SCHEMA_VERSION = 'stage-6c1-evidence-v1'

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

def sha256(path)
  fail_with("file missing: #{path}") unless File.file?(path)

  Digest::SHA256.file(path).hexdigest
end

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  fail_with("malformed JSON #{path}: #{e.message}")
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

def relative_name(path)
  File.basename(path)
end

def require_option(options, key)
  value = options[key]
  fail_with("missing option: #{key}") if value.to_s.empty?

  value
end

def build_manifest(options)
  evidence_dir = require_option(options, :evidence_dir)
  archive = require_option(options, :archive)
  sbom = require_option(options, :sbom)
  scanner_sbom = require_option(options, :scanner_sbom)
  vulnerabilities = require_option(options, :vulnerabilities)
  policy = require_option(options, :policy)
  versions = read_versions(require_option(options, :versions_file))
  policy_result = read_json(policy)
  vulnerability_report = read_json(vulnerabilities)

  {
    'schema_version' => SCHEMA_VERSION,
    'source' => {
      'repository' => options[:source_repository],
      'revision' => options[:source_revision]
    }.compact,
    'target_architecture' => require_option(options, :target_architecture),
    'artifact' => {
      'type' => 'docker-image-archive',
      'filename' => relative_name(archive),
      'sha256' => sha256(archive)
    },
    'runtime' => {
      'loaded_docker_image_id' => require_option(options, :docker_image_id),
      'source_archive_filename' => relative_name(archive),
      'source_archive_sha256' => sha256(archive)
    },
    'sbom' => {
      'tool' => 'syft',
      'tool_version' => require_option(options, :syft_version),
      'expected_tool_version' => normalize_version(versions.fetch('SYFT_VERSION')),
      'catalog_source' => "docker-archive:#{relative_name(archive)}",
      'catalog_source_archive_sha256' => sha256(archive),
      'portable' => {
        'role' => 'PORTABLE_REVIEW_SBOM',
        'format' => 'cyclonedx-json',
        'filename' => relative_name(sbom),
        'sha256' => sha256(sbom),
        'source' => "docker-archive:#{relative_name(archive)}",
        'source_archive_sha256' => sha256(archive)
      },
      'scanner' => {
        'role' => 'SCANNER_NATIVE_SBOM',
        'format' => 'syft-json',
        'filename' => relative_name(scanner_sbom),
        'sha256' => sha256(scanner_sbom),
        'source' => "docker-archive:#{relative_name(archive)}",
        'source_archive_sha256' => sha256(archive)
      }
    },
    'vulnerability_scan' => {
      'tool' => 'grype',
      'tool_version' => require_option(options, :grype_version),
      'expected_tool_version' => normalize_version(versions.fetch('GRYPE_VERSION')),
      'format' => 'json',
      'filename' => relative_name(vulnerabilities),
      'sha256' => sha256(vulnerabilities),
      'source_type' => 'docker-image-archive',
      'source' => "docker-archive:#{relative_name(archive)}",
      'source_archive_sha256' => sha256(archive),
      'database' => vulnerability_report.dig('descriptor', 'db', 'status')
    }.compact,
    'policy' => {
      'version' => policy_result.fetch('policy_version'),
      'filename' => relative_name(policy),
      'sha256' => sha256(policy),
      'source' => relative_name(vulnerabilities),
      'source_vulnerability_report_sha256' => sha256(vulnerabilities),
      'decision' => policy_result.fetch('decision'),
      'blocking_severities' => policy_result.fetch('blocking_severities')
    }
  }
end

def write_manifest(options)
  manifest = build_manifest(options)
  manifest_path = File.join(require_option(options, :evidence_dir), 'evidence-manifest.json')
  sidecar_path = "#{manifest_path}.sha256"
  FileUtils.mkdir_p(File.dirname(manifest_path))
  File.write(manifest_path, "#{JSON.pretty_generate(manifest)}\n")
  File.write(sidecar_path, "#{sha256(manifest_path)}  evidence-manifest.json\n")
  puts '[ok] evidence manifest generated'
end

def validate_manifest(evidence_dir, versions_file)
  manifest_path = File.join(evidence_dir, 'evidence-manifest.json')
  sidecar_path = "#{manifest_path}.sha256"
  manifest = read_json(manifest_path)
  versions = read_versions(versions_file)

  expected_sidecar = "#{sha256(manifest_path)}  evidence-manifest.json"
  actual_sidecar = File.read(sidecar_path).strip
  fail_with('evidence manifest checksum sidecar mismatch') unless actual_sidecar == expected_sidecar

  artifact = manifest.fetch('artifact')
  sbom = manifest.fetch('sbom')
  portable_sbom = sbom.fetch('portable')
  scanner_sbom = sbom.fetch('scanner')
  scan = manifest.fetch('vulnerability_scan')
  policy = manifest.fetch('policy')
  runtime = manifest.fetch('runtime')

  archive_path = File.join(evidence_dir, artifact.fetch('filename'))
  sbom_path = File.join(evidence_dir, portable_sbom.fetch('filename'))
  scanner_sbom_path = File.join(evidence_dir, scanner_sbom.fetch('filename'))
  scan_path = File.join(evidence_dir, scan.fetch('filename'))
  policy_path = File.join(evidence_dir, policy.fetch('filename'))

  fail_with('archive SHA mismatch') unless sha256(archive_path) == artifact.fetch('sha256')
  fail_with('runtime archive SHA mismatch') unless runtime.fetch('source_archive_sha256') == artifact.fetch('sha256')
  fail_with('portable SBOM SHA mismatch') unless sha256(sbom_path) == portable_sbom.fetch('sha256')
  fail_with('scanner SBOM SHA mismatch') unless sha256(scanner_sbom_path) == scanner_sbom.fetch('sha256')
  fail_with('scan report SHA mismatch') unless sha256(scan_path) == scan.fetch('sha256')
  fail_with('policy result SHA mismatch') unless sha256(policy_path) == policy.fetch('sha256')
  fail_with('portable SBOM source does not reference archive') unless portable_sbom.fetch('source') == "docker-archive:#{artifact.fetch('filename')}"
  fail_with('scanner SBOM source does not reference archive') unless scanner_sbom.fetch('source') == "docker-archive:#{artifact.fetch('filename')}"
  fail_with('scan source type is not docker image archive') unless scan.fetch('source_type') == 'docker-image-archive'
  fail_with('scan source does not reference archive') unless scan.fetch('source') == "docker-archive:#{artifact.fetch('filename')}"
  fail_with('scan source hash does not match archive') unless scan.fetch('source_archive_sha256') == artifact.fetch('sha256')
  fail_with('policy source does not reference scan report') unless policy.fetch('source') == scan.fetch('filename')
  fail_with('Syft version does not match pin') unless normalize_version(sbom.fetch('tool_version')) == normalize_version(versions.fetch('SYFT_VERSION'))
  fail_with('Grype version does not match pin') unless normalize_version(scan.fetch('tool_version')) == normalize_version(versions.fetch('GRYPE_VERSION'))

  expected_policy = evaluate(read_json(scan_path))
  actual_policy = read_json(policy_path)
  fail_with('policy decision does not match vulnerability report') unless actual_policy.fetch('decision') == expected_policy.fetch('decision')

  %w[schema_version target_architecture].each do |key|
    fail_with("manifest missing required field: #{key}") unless manifest.key?(key)
  end
  fail_with('runtime image ID missing') if runtime.fetch('loaded_docker_image_id').to_s.empty?
  puts '[ok] evidence manifest validation passed'
end

options = {}
command = ARGV.shift
parser = OptionParser.new do |opts|
  opts.on('--evidence-dir PATH') { |value| options[:evidence_dir] = value }
  opts.on('--archive PATH') { |value| options[:archive] = value }
  opts.on('--sbom PATH') { |value| options[:sbom] = value }
  opts.on('--scanner-sbom PATH') { |value| options[:scanner_sbom] = value }
  opts.on('--vulnerabilities PATH') { |value| options[:vulnerabilities] = value }
  opts.on('--policy PATH') { |value| options[:policy] = value }
  opts.on('--versions-file PATH') { |value| options[:versions_file] = value }
  opts.on('--docker-image-id VALUE') { |value| options[:docker_image_id] = value }
  opts.on('--syft-version VALUE') { |value| options[:syft_version] = value }
  opts.on('--grype-version VALUE') { |value| options[:grype_version] = value }
  opts.on('--grype-db-status VALUE') { |value| options[:grype_db_status] = value }
  opts.on('--target-architecture VALUE') { |value| options[:target_architecture] = value }
  opts.on('--source-repository VALUE') { |value| options[:source_repository] = value }
  opts.on('--source-revision VALUE') { |value| options[:source_revision] = value }
end
parser.parse!(ARGV)

case command
when 'generate'
  write_manifest(options)
when 'validate'
  validate_manifest(require_option(options, :evidence_dir), require_option(options, :versions_file))
else
  fail_with('usage: validate-evidence.rb {generate|validate} [options]')
end
