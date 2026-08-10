#!/usr/bin/env ruby

require "csv"
require "set"

abort("Usage: summarize-locker-ui-hierarchy.rb <compact-hierarchy.csv>") unless ARGV.length == 1

rows = CSV.read(ARGV.fetch(0), headers: true)
abort("Compact hierarchy is missing the attributes column") unless rows.headers&.include?("attributes")

bounded_nodes = rows.each_with_object([]) do |row, values|
  match = row.fetch("attributes").to_s.match(/bounds=\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  next unless match

  bounds = match.captures.map(&:to_i)
  left, top, right, bottom = bounds
  area = (right - left) * (bottom - top)
  values << [Integer(row.fetch("depth")), area, bounds] if area.positive?
end
abort("Compact hierarchy does not contain a bounded top-level window") if bounded_nodes.empty?

# Android exposes unbounded root/window containers before the actual status-bar
# and application windows. Restrict viewport selection to the shallowest depth
# that has bounds, then choose its unique largest geometry. Deeper semantics
# nodes may extend beyond the viewport and must not influence these dimensions.
top_level_depth = bounded_nodes.map(&:first).min
top_level_nodes = bounded_nodes.select { |depth, _, _| depth == top_level_depth }
largest_area = top_level_nodes.map { |_, area, _| area }.max
viewport_bounds = top_level_nodes.each_with_object(Set.new) do |(_, area, bounds), values|
  values << bounds if area == largest_area
end
abort("Compact hierarchy has ambiguous top-level window bounds") unless viewport_bounds.length == 1

screen_left, screen_top, screen_right, screen_bottom = viewport_bounds.first
screen_width = screen_right - screen_left
screen_height = screen_bottom - screen_top
abort("Compact hierarchy root has invalid bounds") unless screen_width.positive? && screen_height.positive?

top_right_action_bounds = rows.each_with_object([]) do |row, values|
  attributes = row.fetch("attributes").to_s
  next unless attributes.split("; ").include?("clickable=true")

  match = attributes.match(/bounds=\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  next unless match

  left, top, right, bottom = match.captures.map(&:to_i)
  next unless left >= screen_left + screen_width * 0.5
  next unless top >= screen_top + screen_height * 0.04
  next unless bottom <= screen_top + screen_height * 0.25

  values << [left, top, right, bottom]
end.to_set

top_right_actions = top_right_action_bounds.length
route_probe = case top_right_actions
when 1 then "all_collections"
when 2 then "collection_page"
else "unknown"
end
blue_visible = rows.any? do |row|
  row.fetch("attributes").to_s.split("; ").any? do |attribute|
    attribute == "text=Blue Suitcase" || attribute == "accessibilityText=Blue Suitcase"
  end
end

puts "capture_status=ok route_probe=#{route_probe} top_right_actions=#{top_right_actions} blue_visible=#{blue_visible}"
