#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

files = Dir.glob('**/*.{yml,yaml}', File::FNM_DOTMATCH).reject { |path| path.start_with?('.git/') }

files.each do |path|
  content = File.read(path)
  begin
    YAML.safe_load(content, aliases: true)
  rescue ArgumentError
    YAML.safe_load(content)
  end
end

puts "[ok] YAML syntax passed for #{files.length} file(s)"
