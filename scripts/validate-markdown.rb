#!/usr/bin/env ruby
# frozen_string_literal: true

files = Dir.glob('**/*.md', File::FNM_DOTMATCH).reject { |path| path.start_with?('.git/', '.tmp/') }
failures = []

files.each do |path|
  content = File.read(path)
  content.each_line.with_index(1) do |line, number|
    failures << "#{path}:#{number}: trailing whitespace" if line.match?(/[ \t]\n\z/)
    failures << "#{path}:#{number}: internal application link is not public documentation" if line.include?('ca://')
  end

  content.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.each do |target|
    next if target.start_with?('http://', 'https://', 'mailto:', '#')
    next if target.empty?

    target_path = target.split('#', 2).first
    next if target_path.empty?

    resolved = File.expand_path(target_path, File.dirname(path))
    failures << "#{path}: broken local Markdown link: #{target}" unless File.exist?(resolved)
  end
end

if failures.any?
  warn failures.join("\n")
  exit 1
end

puts "[ok] Markdown hygiene and local links passed"
