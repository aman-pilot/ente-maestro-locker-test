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
platform_state = classes.fetch("platformStateDeferred").keys
paid = classes.fetch("paidDeferred").keys
classified = hosted + unresolved + native + platform_state + paid
fail_check("scenario classifications contain duplicates") unless classified.uniq.length == classified.length

fail_check("expected 20 proven hosted candidates") unless hosted.length == 20
fail_check("expected six unresolved core flows") unless unresolved.length == 6
fail_check("expected three native-system flows") unless native.length == 3
fail_check("expected one deferred platform-state flow") unless platform_state.length == 1
fail_check("expected one paid flow") unless paid.length == 1

directory_for = lambda do |scenario_id|
  return "paid" if paid.include?(scenario_id)
  return "platform" if (native + platform_state).include?(scenario_id)

  nil
end

expected_paths = classified.to_h do |scenario_id|
  directory = directory_for.call(scenario_id)
  relative_path = ["maestro/locker/online", directory, "#{scenario_id}.yaml"].compact.join("/")
  [scenario_id, relative_path]
end
on_disk = Dir.glob(ROOT.join("maestro/locker/online/**/*.yaml")).map do |path|
  Pathname.new(path).relative_path_from(ROOT).to_s
end.reject { |path| path.start_with?("maestro/locker/online/subflows/") }.sort
fail_check("canonical YAML inventory differs from the registry") unless on_disk == expected_paths.values.sort

forbidden = /USER_EMAIL|USER_PASSWORD|MUSEUM_ENDPOINT|clearState\s*:|appId:\s+io\.ente\.locker|fresh[- ]account|every workflow gets its own account/
allowed_product_subflows = [
  "subflows/open-navigation-menu.yaml",
  "../subflows/open-navigation-menu.yaml"
]
on_disk.each do |relative_path|
  body = ROOT.join(relative_path).read
  fail_check("#{relative_path} must use the runtime APP_ID") unless body.start_with?("appId: ${APP_ID}\n---\n")
  fail_check("#{relative_path} crosses the product/runtime boundary") if body.match?(forbidden)
  dependencies = body.scan(/^\s*file:\s*["']?([^"'\s]+)["']?\s*$/).flatten
  unexpected_dependencies = dependencies - allowed_product_subflows
  fail_check("#{relative_path} references an external Maestro flow") unless unexpected_dependencies.empty?
end

login_path = ROOT.join("maestro/locker/online/subflows/login-online-account.yaml")
fail_check("missing private runtime login flow") unless login_path.file?
login_body = login_path.read
fail_check("runtime login must use the runtime APP_ID") unless login_body.start_with?("appId: ${APP_ID}\n---\n")
fail_check("runtime login must not clear state inside Maestro") if login_body.match?(/clearState\s*:/)
%w[USER_EMAIL USER_PASSWORD].each do |variable|
  fail_check("runtime login is missing #{variable}") unless login_body.include?("${#{variable}}")
end
fail_check("runtime login must receive the endpoint through app data") if login_body.include?("MUSEUM_ENDPOINT")

drawer_path = ROOT.join("maestro/locker/online/subflows/open-navigation-menu.yaml")
fail_check("missing shared drawer compatibility flow") unless drawer_path.file?
drawer_body = drawer_path.read
fail_check("drawer compatibility flow must use the runtime APP_ID") unless drawer_body.start_with?("appId: ${APP_ID}\n---\n")
fail_check("drawer compatibility flow must prefer the accessibility semantic") unless drawer_body.include?("visible: Open navigation menu")
fail_check("drawer compatibility flow must retain the published-build coordinate fallback") unless drawer_body.include?("point: 9%,8%")

credential_yaml = Dir.glob(ROOT.join("maestro/locker/**/*.yaml")).select do |path|
  File.read(path).match?(/USER_EMAIL|USER_PASSWORD/)
end
fail_check("credentials escaped the single private login flow") unless credential_yaml == [login_path.to_s]
endpoint_yaml = Dir.glob(ROOT.join("maestro/locker/**/*.yaml")).select do |path|
  File.read(path).include?("MUSEUM_ENDPOINT")
end
fail_check("the Museum endpoint escaped app-data preparation") unless endpoint_yaml.empty?

flow_lines = on_disk.map do |relative_path|
  "#{Digest::SHA256.file(ROOT.join(relative_path)).hexdigest}  #{relative_path}\n"
end.join
actual_flow_set_hash = Digest::SHA256.hexdigest(flow_lines)
expected_flow_set_hash = registry.dig("import", "flowSetSha256")
fail_check("canonical flow-set hash differs from provenance") unless actual_flow_set_hash == expected_flow_set_hash

hosted_lane = registry.fetch("hostedLane")
expected_hosted_flows = %w[
  empty-home-and-save-options
  empty-trash
  search-note-secret-and-thing
  search-with-no-results
  view-account-and-security-settings
  search-settings-and-open-account
  view-about-and-support-settings
  view-theme-options
  change-language-and-restore-english
  empty-collection
  filter-items-by-collection
  view-collection-and-item-action-menus
  add-item-to-multiple-collections
  mark-and-unmark-important
  select-all-and-mark-important
  bulk-add-delete-and-restore-items
  delete-collection-keep-item
  edit-emergency-contact
  permanently-delete-note
  logout
]
expected_lane_contract = {
  "mode" => "online-only",
  "accountCount" => 1,
  "fixtureApplications" => 1,
  "backendResets" => 0,
  "seedBeforeFlow" => "search-note-secret-and-thing",
  "flows" => expected_hosted_flows
}
fail_check("hosted lane differs from the audited online-only contract") unless hosted_lane == expected_lane_contract
fail_check("catalog online fixture must be applied once") unless catalog.dig("onlineFixture", "applyCount") == 1
fail_check("hosted lane must contain every hosted candidate exactly once") unless hosted_lane.fetch("flows").sort == hosted.sort
hosted_lane.fetch("flows").each do |scenario_id|
  fail_check("hosted lane contains a non-hosted scenario: #{scenario_id}") unless hosted.include?(scenario_id)
end

puts "Locker product flows are canonical: #{on_disk.length} YAML files (#{hosted.length} hosted candidates, #{classified.length - hosted.length} deferred or unresolved)"
