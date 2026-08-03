#!/usr/bin/env ruby

require "set"
require "yaml"

SENSITIVE_TRIGGERS = %w[
  pull_request_target
  issue_comment
  pull_request_review_comment
  discussion_comment
  workflow_run
].to_set.freeze

CHECKED_PATHS = [".github/workflows/*.{yml,yaml}"].freeze
USES_REF = %r{\A([A-Za-z0-9._-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._/-]+)?)@(\S+)\z}
FULL_SHA = /\A[0-9a-fA-F]{40}\z/

def workflow_yaml(path)
  YAML.safe_load(File.read(path), aliases: true) || {}
rescue Psych::Exception => e
  abort("Failed to parse workflow YAML in #{path}: #{e.message}")
end

def trigger_names(workflow)
  events = workflow["on"] || workflow[true]
  return [events] if events.is_a?(String)
  return events.grep(String) if events.is_a?(Array)
  return events.keys.map(&:to_s) if events.is_a?(Hash)

  []
end

def uses_values(node)
  case node
  when Hash
    node.flat_map do |key, value|
      [key.to_s == "uses" && value.is_a?(String) ? value : nil, *uses_values(value)]
    end.compact
  when Array
    node.flat_map { |value| uses_values(value) }
  else
    []
  end
end

checked_files = CHECKED_PATHS.flat_map { |path| Dir.glob(path) }.sort
trigger_violations = []
unpinned_violations = []

checked_files.each do |path|
  workflow = workflow_yaml(path)
  (trigger_names(workflow).to_set & SENSITIVE_TRIGGERS).each do |trigger|
    trigger_violations << "#{path}: #{trigger}"
  end
  uses_values(workflow).each do |uses|
    action, ref = uses.match(USES_REF)&.captures
    next unless action
    next if ref.match?(FULL_SHA)

    unpinned_violations << "#{path}: #{action}@#{ref}"
  end
end

failed = trigger_violations.any? || unpinned_violations.any?
puts "Workflow Security Checks: #{failed ? "Failed" : "Passed"}"
puts "Checked #{checked_files.length} workflow files."

unless trigger_violations.empty?
  puts "Privileged triggers:"
  trigger_violations.each { |violation| puts "- #{violation}" }
end
unless unpinned_violations.empty?
  puts "Unpinned external actions:"
  unpinned_violations.each { |violation| puts "- #{violation}" }
end

exit(failed ? 1 : 0)
