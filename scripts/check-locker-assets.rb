#!/usr/bin/env ruby

require "digest"
require "json"
require "pathname"
require "psych"

ROOT = Pathname.new(__dir__).join("..").expand_path
LOCKER = ROOT.join("locker")

def fail_check(message)
  abort("Locker asset check failed: #{message}")
end

def inside_locker(relative_path)
  path = LOCKER.join(relative_path).cleanpath
  prefix = "#{LOCKER}#{File::SEPARATOR}"
  fail_check("path escapes locker/: #{relative_path}") unless path.to_s.start_with?(prefix)
  path
end

def load_json(path)
  JSON.parse(path.read)
rescue JSON::ParserError => error
  fail_check("invalid JSON in #{path.relative_path_from(ROOT)}: #{error.message}")
end

def item_name(item, manifest_dir)
  return item["title"] if item["title"]
  return item["name"] if item["name"]
  return File.basename(item.fetch("path")) if item["type"] == "document"

  fail_check("item #{item["ref"].inspect} has no visible name in #{manifest_dir}")
end

catalog_path = LOCKER.join("catalog.v1.json")
catalog = load_json(catalog_path)
fail_check("catalog schemaVersion must be 1") unless catalog["schemaVersion"] == 1
expected_account_lifecycle = {
  "status" => "single-online-account-per-run",
  "contract" => "One synthetic online account is created for an isolated run. The shared fixture is applied once, related flows reuse its backend state, and the disposable stack is removed after the lane."
}
fail_check("catalog must declare the single online account contract") unless catalog["accountLifecycle"] == expected_account_lifecycle

forbidden_catalog_keys = %w[entries fixtureProfiles historicalEvidence isolation referenceManifests runtimeValidation scenarios suiteRoot supportManifests]
present_forbidden = forbidden_catalog_keys & catalog.keys
fail_check("catalog retains legacy keys: #{present_forbidden.join(", ")}") unless present_forbidden.empty?

online_fixture = catalog.fetch("onlineFixture")
planned_manifests = catalog.fetch("plannedManifests")
fail_check("the online fixture must be applied exactly once") unless online_fixture["applyCount"] == 1

manifest_cache = {}
load_manifest = lambda do |relative_path|
  manifest_path = inside_locker(relative_path)
  fail_check("missing manifest #{relative_path}") unless manifest_path.file?
  manifest_cache[relative_path] ||= begin
    manifest = load_json(manifest_path)
    fail_check("#{relative_path} must use manifest version 1") unless manifest["version"] == 1
    collections = manifest["collections"]
    items = manifest["items"]
    fail_check("#{relative_path} collections must be an array") unless collections.is_a?(Array)
    fail_check("#{relative_path} items must be an array") unless items.is_a?(Array)

    collection_refs = collections.map { |entry| entry.fetch("ref") }
    item_refs = items.map { |entry| entry.fetch("ref") }
    all_refs = collection_refs + item_refs
    fail_check("#{relative_path} has duplicate fixture refs") unless all_refs.uniq.length == all_refs.length

    items.each do |item|
      Array(item["collections"]).each do |collection_ref|
        fail_check("#{relative_path} item #{item.fetch("ref")} references unknown collection #{collection_ref}") unless collection_refs.include?(collection_ref)
      end
      next unless item["type"] == "document"

      document = manifest_path.dirname.join(item.fetch("path")).cleanpath
      fail_check("document path escapes locker/: #{item.fetch("path")}") unless document.to_s.start_with?("#{LOCKER}#{File::SEPARATOR}")
      fail_check("missing document fixture #{document.relative_path_from(ROOT)}") unless document.file?
    end
    manifest
  end
end

online_manifest_path = online_fixture.fetch("manifest")
online_manifest = load_manifest.call(online_manifest_path)
collection_names = online_manifest.fetch("collections").map { |entry| entry.fetch("name") }.sort
item_names = online_manifest.fetch("items").map { |item| item_name(item, online_manifest_path) }.sort
fail_check("online fixture collection summary differs from #{online_manifest_path}") unless online_fixture.fetch("collections").sort == collection_names
fail_check("online fixture item summary differs from #{online_manifest_path}") unless online_fixture.fetch("items").sort == item_names

fail_check("planned manifests contain duplicates") unless planned_manifests.uniq.length == planned_manifests.length
planned_manifests.each { |relative_path| load_manifest.call(relative_path) }
classified = ([online_manifest_path] + planned_manifests).uniq.sort
on_disk = Dir.glob(LOCKER.join("manifests/*.json")).map { |path| Pathname.new(path).relative_path_from(LOCKER).to_s }.sort
fail_check("manifest classification differs from files on disk") unless classified == on_disk

provenance = load_json(LOCKER.join("provenance.v1.json"))
fail_check("provenance schemaVersion must be 1") unless provenance["schemaVersion"] == 1
provenance.fetch("fixtures").each do |relative_path, expected_hash|
  fixture_path = ROOT.join(relative_path).cleanpath
  fail_check("provenance fixture escapes repository: #{relative_path}") unless fixture_path.to_s.start_with?("#{ROOT}#{File::SEPARATOR}")
  fail_check("missing provenance fixture #{relative_path}") unless fixture_path.file?
  actual_hash = Digest::SHA256.file(fixture_path).hexdigest
  fail_check("fixture hash mismatch for #{relative_path}") unless actual_hash == expected_hash
end

manifest_lines = Dir.glob(LOCKER.join("manifests/*.json")).sort.map do |path|
  relative_path = Pathname.new(path).relative_path_from(ROOT)
  "#{Digest::SHA256.file(path).hexdigest}  #{relative_path}\n"
end.join
manifest_set_hash = Digest::SHA256.hexdigest(manifest_lines)
fail_check("manifest set hash differs from provenance") unless manifest_set_hash == provenance.fetch("manifestSetSha256")

cargo = ROOT.join("tools/locker-seed/Cargo.toml").read
revision = provenance.fetch("enteGitRevision")
fail_check("Cargo dependencies do not both use the provenance Ente revision") unless cargo.scan(/rev = "#{Regexp.escape(revision)}"/).length == 2
fail_check("Cargo still contains path dependencies") if cargo.match?(/\bpath\s*=/)

compose_path = LOCKER.join("stack/compose.yaml")
compose = Psych.safe_load(compose_path.read, aliases: false)
services = compose.fetch("services")
service_for_image = {
  "museum" => "museum",
  "postgres" => "postgres",
  "minio" => "minio",
  "minioClient" => "minio-init",
  "socat" => "socat"
}
provenance.fetch("images").each do |key, image|
  fail_check("image #{key} is not digest pinned") unless image.match?(/@sha256:[0-9a-f]{64}\z/)
  service = service_for_image.fetch(key)
  fail_check("Compose image for #{service} differs from provenance") unless services.dig(service, "image") == image
end
services.each do |service, definition|
  fail_check("Compose service #{service} must not build source") if definition.key?("build")
  fail_check("Compose service #{service} must not extend another file") if definition.key?("extends")
end

puts "Locker assets are aligned: one online fixture, #{planned_manifests.length} planned manifests"
