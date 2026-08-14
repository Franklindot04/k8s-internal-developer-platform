#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require_relative 'publication'

def fail_with(message)
  warn "[error] #{message}"
  exit 1
end

def read_json(path)
  JSON.parse(File.read(path))
rescue JSON::ParserError => e
  fail_with("malformed JSON #{path}: #{e.message}")
end

command = ARGV.shift
options = {}
parser = OptionParser.new do |opts|
  opts.on('--publication PATH') { |value| options[:publication] = value }
  opts.on('--handoff PATH') { |value| options[:handoff] = value }
  opts.on('--versions-file PATH') { |value| options[:versions_file] = value }
end
parser.parse!(ARGV)

begin
  versions_file = options[:versions_file] || 'scripts/supply-chain/versions.env'
  case command
  when 'validate-publication'
    path = options[:publication] || fail_with('missing option: --publication')
    SupplyChainPublication.validate_manifest_file!(path, versions_file: versions_file)
    puts '[ok] publication evidence validation passed'
  when 'validate-handoff'
    publication_path = options[:publication] || fail_with('missing option: --publication')
    handoff_path = options[:handoff] || fail_with('missing option: --handoff')
    manifest = SupplyChainPublication.validate_manifest_file!(publication_path, versions_file: versions_file)
    SupplyChainPublication.validate_handoff_object!(read_json(handoff_path), manifest)
    puts '[ok] image reference handoff validation passed'
  else
    fail_with('usage: validate-publication.rb {validate-publication|validate-handoff} [options]')
  end
rescue SupplyChainPublication::ContractError => e
  fail_with(e.message)
end
