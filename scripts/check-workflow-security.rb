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
EXPECTED_WORKFLOW_NAMES = {
  "locker-android-online.yml" => "Locker Android online",
  "locker-android-smoke.yml" => "Locker Android smoke",
  "locker-static.yml" => "Locker validation"
}.freeze
EXPECTED_RUN_NAMES = {
  "locker-android-online.yml" => "Locker Android online · ${{ inputs.flow || 'all' }}",
  "locker-android-smoke.yml" => "Locker Android smoke · ${{ inputs.suite || 'all' }}"
}.freeze
EXPECTED_TRIGGERS = {
  "locker-android-online.yml" => %w[pull_request push workflow_dispatch],
  "locker-android-smoke.yml" => %w[pull_request push workflow_dispatch],
  "locker-static.yml" => %w[pull_request push workflow_dispatch]
}.freeze
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

def workflow_steps(workflow)
  workflow.fetch("jobs", {}).values.flat_map { |job| job.fetch("steps", []) }
end

def run_body(step)
  step["run"].is_a?(String) ? step["run"] : ""
end

def input_value(step, key)
  inputs = step["with"]
  inputs.is_a?(Hash) ? inputs[key] : nil
end

checked_files = CHECKED_PATHS.flat_map { |path| Dir.glob(path) }.sort
trigger_violations = []
unpinned_violations = []
published_apk_violations = []
workflow_contract_violations = []

checked_files.each do |path|
  workflow = workflow_yaml(path)
  basename = File.basename(path)
  steps = workflow_steps(workflow)
  (trigger_names(workflow).to_set & SENSITIVE_TRIGGERS).each do |trigger|
    trigger_violations << "#{path}: #{trigger}"
  end
  uses_values(workflow).each do |uses|
    action, ref = uses.match(USES_REF)&.captures
    next unless action
    next if ref.match?(FULL_SHA)

    unpinned_violations << "#{path}: #{action}@#{ref}"
  end

  unless workflow["permissions"] == { "contents" => "read" }
    workflow_contract_violations << "#{path}: permissions must be limited to contents: read"
  end
  unless workflow["name"] == EXPECTED_WORKFLOW_NAMES.fetch(basename)
    workflow_contract_violations << "#{path}: public workflow name differs from the Locker naming convention"
  end
  expected_run_name = EXPECTED_RUN_NAMES[basename]
  if expected_run_name && workflow["run-name"] != expected_run_name
    workflow_contract_violations << "#{path}: run name must expose the selected scope"
  end
  unless trigger_names(workflow).sort == EXPECTED_TRIGGERS.fetch(basename).sort
    workflow_contract_violations << "#{path}: triggers differ from the Locker automatic CI contract"
  end
  steps.select { |step| step["uses"].to_s.start_with?("actions/checkout@") }.each do |step|
    next if input_value(step, "persist-credentials") == false

    workflow_contract_violations << "#{path}: every checkout must set persist-credentials: false"
  end

  next unless basename.start_with?("locker-android-")

  resolver_step = steps.find { |step| step["id"] == "release" }
  download_step = steps.find { |step| step["id"] == "download-apk" }
  verify_step = steps.find { |step| step["id"] == "verify-apk" }
  emulator_step = steps.find do |step|
    step["uses"].to_s.start_with?("ReactiveCircus/android-emulator-runner@")
  end
  unless run_body(resolver_step || {}).strip ==
      'scripts/resolve-nightly-apk.sh --app locker --github-output "$GITHUB_OUTPUT"' &&
      run_body(download_step || {}).include?("releases/assets/$APK_ASSET_ID") &&
      run_body(verify_step || {}).include?("actual_sha256") &&
      run_body(verify_step || {}).include?("$LOCKER_APK_SHA256") &&
      input_value(emulator_step || {}, "script").to_s.include?('--apk "$LOCKER_APK_PATH"')
    published_apk_violations << "#{path}: must resolve, download, verify, and run an ente/nightly Locker APK"
  end
  if steps.any? { |step| run_body(step).match?(/(?:flutter\s+build|gradlew?\s+[^\n]*assemble)/i) }
    published_apk_violations << "#{path}: must not compile the Locker application"
  end

  next unless basename == "locker-android-online.yml"

  jobs = workflow.fetch("jobs")
  resolve_job = jobs.fetch("resolve")
  online_job = jobs.fetch("online")
  gate_job = jobs.fetch("locker-online-gate")
  scope_step = resolve_job.fetch("steps").find { |step| step["id"] == "scope" }
  online_steps = online_job.fetch("steps")
  online_emulator_step = online_steps.find do |step|
    step["uses"].to_s.start_with?("ReactiveCircus/android-emulator-runner@")
  end
  artifact_step = online_steps.find do |step|
    step["uses"].to_s.start_with?("actions/upload-artifact@")
  end
  artifact_paths = input_value(artifact_step || {}, "path").to_s.lines.map(&:strip).reject(&:empty?)

  expected_scope_output = "${{ steps.scope.outputs.selected_flow }}"
  expected_selected_flow = "${{ needs.resolve.outputs.selected_flow }}"
  expected_gate_name = "Require online tests · ${{ needs.resolve.outputs.selected_flow || inputs.flow || 'unresolved' }}"
  expected_concurrency_group = "locker-android-online-${{ github.ref }}-${{ inputs.flow || 'all' }}"
  expected_android_api = 34
  expected_android_target = "default"
  expected_emulator_build = 12_414_864
  expected_emulator_options = "-no-window -gpu swiftshader_indirect -feature -Vulkan -no-metrics -no-snapshot -noaudio -no-boot-anim -memory 6144"
  expected_artifact_paths = [
    "artifacts/maestro/online/results/*.xml",
    "artifacts/maestro/online/summary.txt",
    "artifacts/maestro/online/diagnostics/*-ui.txt"
  ]

  unless workflow.dig("concurrency", "group") == expected_concurrency_group &&
      workflow.dig("concurrency", "cancel-in-progress") == true
    workflow_contract_violations << "#{path}: concurrency must isolate full and targeted scopes"
  end
  unless resolve_job.dig("outputs", "selected_flow") == expected_scope_output &&
      resolve_job["name"] == "Plan online tests" &&
      scope_step&.dig("env", "REQUESTED_FLOW") == "${{ inputs.flow || 'all' }}" &&
      run_body(scope_step || {}).include?('scripts/select-locker-seeded-flow.sh "$REQUESTED_FLOW"') &&
      online_job["name"] == "Run online tests · ${{ needs.resolve.outputs.selected_flow }}" &&
      online_job.dig("env", "LOCKER_SELECTED_FLOW") == expected_selected_flow &&
      input_value(online_emulator_step || {}, "script") ==
        'scripts/run-locker-seeded-hosted.sh --apk "$LOCKER_APK_PATH"'
    workflow_contract_violations << "#{path}: selected flow must pass through the audited selector and hosted wrapper"
  end
  unless online_job["timeout-minutes"] == 60
    workflow_contract_violations << "#{path}: the sequential full lane must retain a 60-minute timeout"
  end
  unless workflow.dig("env", "LOCKER_ANDROID_API") == expected_android_api &&
      workflow.dig("env", "LOCKER_ANDROID_TARGET") == expected_android_target &&
      workflow.dig("env", "LOCKER_EMULATOR_BUILD") == expected_emulator_build &&
      workflow.dig("env", "LOCKER_EMULATOR_OPTIONS") == expected_emulator_options &&
      input_value(online_emulator_step || {}, "api-level") == "${{ env.LOCKER_ANDROID_API }}" &&
      input_value(online_emulator_step || {}, "emulator-build") == "${{ env.LOCKER_EMULATOR_BUILD }}" &&
      input_value(online_emulator_step || {}, "target") == "${{ env.LOCKER_ANDROID_TARGET }}" &&
      input_value(online_emulator_step || {}, "arch") == "x86_64" &&
      input_value(online_emulator_step || {}, "profile") == "pixel_5" &&
      input_value(online_emulator_step || {}, "cores") == 4 &&
      input_value(online_emulator_step || {}, "disable-animations") == true &&
      input_value(online_emulator_step || {}, "emulator-options") == "${{ env.LOCKER_EMULATOR_OPTIONS }}"
    workflow_contract_violations << "#{path}: hosted Android and emulator versions must remain pinned to the proven Auth-compatible environment"
  end
  unless gate_job["name"] == expected_gate_name
    workflow_contract_violations << "#{path}: the final gate name must expose full versus targeted scope"
  end
  unless artifact_paths == expected_artifact_paths
    workflow_contract_violations << "#{path}: online artifacts must remain limited to redacted JUnit, summary, and route probes"
  end
end

failed = trigger_violations.any? || unpinned_violations.any? ||
  published_apk_violations.any? || workflow_contract_violations.any?
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
unless published_apk_violations.empty?
  puts "Published Locker APK contract violations:"
  published_apk_violations.each { |violation| puts "- #{violation}" }
end
unless workflow_contract_violations.empty?
  puts "Workflow contract violations:"
  workflow_contract_violations.each { |violation| puts "- #{violation}" }
end

exit(failed ? 1 : 0)
