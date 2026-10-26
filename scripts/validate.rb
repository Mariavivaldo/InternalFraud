#!/usr/bin/env ruby
# Checks briefing files and reports problems in plain language.
#
#   ruby scripts/validate.rb                      # check every file in _posts/
#   ruby scripts/validate.rb _posts/2026-10-26-briefing.md   # check one file
#
# Exits with status 1 if any file has errors (this stops the GitHub Actions build).

require_relative "../lib/briefing_validator"

root = File.expand_path("..", __dir__)
files = ARGV.empty? ? Dir[File.join(root, "_posts", "*.{md,markdown}")].sort : ARGV

if files.empty?
  puts "No briefing files found in _posts/ yet. Nothing to check."
  exit 0
end

failed = 0
dates = Hash.new { |h, k| h[k] = [] }

files.each do |path|
  unless File.file?(path)
    puts "✗ #{path}\n    error: file not found"
    failed += 1
    next
  end
  rel = path.sub("#{root}/", "")
  res = Briefing.validate_file(path)
  dates[res.date] << rel if res.date
  if res.ok?
    regions = Array(res.data["regions"]).size
    incidents = Array(res.data["incidents"]).size
    puts "✓ #{rel} (#{regions} region#{'s' unless regions == 1}, #{incidents} incident#{'s' unless incidents == 1})"
  else
    failed += 1
    puts "✗ #{rel}"
    res.errors.each { |e| puts "    error: #{e}" }
  end
  res.warnings.each { |w| puts "    warning: #{w}" }
end

dates.each do |date, paths|
  next if paths.size < 2
  failed += 1
  puts "✗ more than one briefing is dated #{date}: #{paths.join(', ')}"
end

puts
if failed.zero?
  puts "#{files.size} file#{'s' unless files.size == 1} checked, no errors."
else
  puts "#{files.size} file#{'s' unless files.size == 1} checked, #{failed} with errors. Nothing will be published until they are fixed."
  exit 1
end
