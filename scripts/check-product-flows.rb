#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"

ROOT = Pathname.new(__dir__).join("..").expand_path

def fail_check(message)
  abort("Locker product flow check failed: #{message}")
end

def load_json(relative_path)
  JSON.parse(ROOT.join(relative_path).read)
rescue JSON::ParserError => error
  fail_check("invalid JSON in #{relative_path}: #{error.message}")
end

catalog = load_json("locker/catalog.v1.json")
registry = load_json("locker/product-flows.v1.json")
fail_check("registry schemaVersion must be 1") unless registry["schemaVersion"] == 1
fail_check("this repository must own the canonical flows") unless registry["canonicalOwner"] == "aman-pilot/ente-maestro-locker-test"

source = registry.fetch("sourceSnapshot")
fail_check("the Ente revision is a base revision, not a false content claim") unless source["worktreeState"] == "untracked-source-assets"
%w[flowSetSha256 fixtureMapSha256 manifestSetSha256].each do |key|
  fail_check("invalid source #{key}") unless source.fetch(key).match?(/\A[0-9a-f]{64}\z/)
end

classes = registry.fetch("classifications")
hosted = classes.fetch("hostedCandidate")
unresolved = classes.fetch("hostedUnresolved").keys
native = classes.fetch("nativeSystemDeferred").keys
offline = classes.fetch("platformOfflineDeferred").keys
paid = classes.fetch("paidDeferred").keys
classified = hosted + unresolved + native + offline + paid
fail_check("scenario classifications contain duplicates") unless classified.uniq.length == classified.length

scenario_by_id = catalog.fetch("scenarios").to_h { |scenario| [scenario.fetch("scenarioId"), scenario] }
fail_check("classification differs from the catalog scenarios") unless classified.sort == scenario_by_id.keys.sort
fail_check("expected 25 hosted candidates") unless hosted.length == 25
fail_check("expected one unresolved core flow") unless unresolved.length == 1
fail_check("expected three native-system flows") unless native.length == 3
fail_check("expected one platform/offline flow") unless offline.length == 1
fail_check("expected one paid flow") unless paid.length == 1

lane_for = lambda do |scenario_id|
  return "paid" if paid.include?(scenario_id)
  return "platform" if (native + offline).include?(scenario_id)

  "core"
end

expected_paths = classified.to_h do |scenario_id|
  [scenario_id, "maestro/locker/online/#{lane_for.call(scenario_id)}/#{scenario_id}.yaml"]
end
on_disk = Dir.glob(ROOT.join("maestro/locker/online/**/*.yaml")).map do |path|
  Pathname.new(path).relative_path_from(ROOT).to_s
end.sort
fail_check("canonical YAML inventory differs from the registry") unless on_disk == expected_paths.values.sort

forbidden = /USER_EMAIL|USER_PASSWORD|MUSEUM_ENDPOINT|clearState\s*:|appId:\s+io\.ente\.locker|fresh[- ]account|every workflow gets its own account/
on_disk.each do |relative_path|
  body = ROOT.join(relative_path).read
  fail_check("#{relative_path} must use the runtime APP_ID") unless body.start_with?("appId: ${APP_ID}\n---\n")
  fail_check("#{relative_path} crosses the product/runtime boundary") if body.match?(forbidden)
  fail_check("#{relative_path} references an external Maestro flow") if body.match?(/runFlow:\s*\n\s+file:/)
end

login_path = ROOT.join("maestro/locker/runtime/login-seeded-account.yaml")
fail_check("missing private runtime login flow") unless login_path.file?
login_body = login_path.read
fail_check("runtime login must use the runtime APP_ID") unless login_body.start_with?("appId: ${APP_ID}\n---\n")
fail_check("runtime login must not clear state inside Maestro") if login_body.match?(/clearState\s*:/)
%w[USER_EMAIL USER_PASSWORD MUSEUM_ENDPOINT].each do |variable|
  fail_check("runtime login is missing #{variable}") unless login_body.include?("${#{variable}}")
end

credential_yaml = Dir.glob(ROOT.join("maestro/locker/**/*.yaml")).select do |path|
  File.read(path).match?(/USER_EMAIL|USER_PASSWORD|MUSEUM_ENDPOINT/)
end
fail_check("credentials escaped the single private login flow") unless credential_yaml == [login_path.to_s]

flow_lines = on_disk.map do |relative_path|
  "#{Digest::SHA256.file(ROOT.join(relative_path)).hexdigest}  #{relative_path}\n"
end.join
actual_flow_set_hash = Digest::SHA256.hexdigest(flow_lines)
expected_flow_set_hash = registry.dig("import", "flowSetSha256")
fail_check("canonical flow-set hash differs from provenance") unless actual_flow_set_hash == expected_flow_set_hash

initial_proof = registry.fetch("initialHostedProof")
expected_initial_proof = %w[
  empty-home-and-save-options
  search-note-secret-and-thing
  view-account-and-security-settings
  search-settings-and-open-account
]
fail_check("initial hosted proof must remain the audited non-native subset") unless initial_proof == expected_initial_proof
initial_proof.each do |scenario_id|
  fail_check("initial proof contains a non-hosted scenario: #{scenario_id}") unless hosted.include?(scenario_id)
  scenario = scenario_by_id.fetch(scenario_id)
  fail_check("initial proof has selector blockers: #{scenario_id}") unless Array(scenario["selectorBlockers"]).empty?
  status = scenario.dig("historicalEvidence", "migrationStatus")
  fail_check("initial proof lacks validated-pass evidence: #{scenario_id}") unless status == "validated-pass"
end

puts "Locker product flows are canonical: #{on_disk.length} YAML files (#{hosted.length} hosted candidates, #{classified.length - hosted.length} deferred or unresolved)"
