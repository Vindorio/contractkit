#!/usr/bin/env ruby
# Parse ISSUES.md and create GitHub issues with labels + milestones.
# Idempotency: re-running creates duplicates. Run once.

require "tempfile"
require "shellwords"

REPO = "gudetimes1234/contractkit"
ISSUES_MD = File.join(__dir__, "..", "ISSUES.md")

MILESTONE_MAP = {
  "M0" => "M0 — Scaffolding",
  "M1" => "M1 — Core Clients",
  "M2" => "M2 — Data Models",
  "M3" => "M3 — Ship It",
}

content = File.read(ISSUES_MD)

current_milestone = nil
issues = []
current_issue = nil

content.each_line do |line|
  if (m = line.match(/^## Milestone (M\d)/))
    current_milestone = m[1]
    next
  end

  if (m = line.match(/^### #(\d+) (.+)$/))
    issues << current_issue if current_issue
    current_issue = {
      number_in_doc: m[1],
      title: m[2].strip,
      milestone: current_milestone,
      labels: [],
      body_lines: [],
    }
    next
  end

  next unless current_issue

  if (m = line.match(/^\*\*Labels:\*\* (.+)$/))
    current_issue[:labels] = m[1].scan(/`([^`]+)`/).flatten
  end

  current_issue[:body_lines] << line
end

issues << current_issue if current_issue

# Drop the dependency graph and critical path sections that bleed past #30
issues.reject! { |i| i[:title].start_with?("Dependency graph") }

puts "Parsed #{issues.size} issues."
puts

issues.each do |issue|
  body = issue[:body_lines].join.strip
  milestone_full = MILESTONE_MAP[issue[:milestone]]

  Tempfile.create(["issue-#{issue[:number_in_doc]}-", ".md"]) do |f|
    f.write(body)
    f.flush

    cmd = [
      "gh", "issue", "create",
      "--repo", REPO,
      "--title", issue[:title],
      "--body-file", f.path,
      "--milestone", milestone_full,
    ]
    issue[:labels].each { |l| cmd << "--label" << l }

    print "[#{issue[:number_in_doc]}] #{issue[:title][0, 60]}... "
    out = `#{cmd.shelljoin} 2>&1`
    if $?.success?
      url = out.lines.last.strip
      puts "OK #{url}"
    else
      puts "FAILED"
      puts out.lines.map { |l| "    #{l}" }.join
    end
  end
end
