#!/usr/bin/env ruby

require "csv"
require "set"

abort("Usage: summarize-locker-ui-hierarchy.rb <compact-hierarchy.csv>") unless ARGV.length == 1

def exact_semantics_visible?(rows, expected)
  rows.any? do |row|
    row.fetch("attributes").to_s.split("; ").any? do |attribute|
      value = if attribute.start_with?("text=")
        attribute.sub("text=", "")
      elsif attribute.start_with?("accessibilityText=")
        attribute.sub("accessibilityText=", "")
      end
      value&.gsub("\\n", "\n") == expected
    end
  end
end

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
collection_row_visible = exact_semantics_visible?(rows, "Home Inventory\n2 items")
collection_title_visible = exact_semantics_visible?(rows, "Home Inventory")
travel_archive_row_visible = rows.any? do |row|
  row.fetch("attributes").to_s.split("; ").any? do |attribute|
    value = attribute.sub(/\A(?:text|accessibilityText)=/, "")
    attribute.match?(/\A(?:text|accessibilityText)=/) && value.gsub("\\n", "\n").start_with?("Travel Archive\n")
  end
end
travel_archive_title_visible = exact_semantics_visible?(rows, "Travel Archive")
empty_heading_visible = exact_semantics_visible?(rows, "Nothing to see here")
empty_description_visible = exact_semantics_visible?(rows, "There are no items in this collection")
route_probe = if collection_row_visible
  "all_collections"
elsif collection_title_visible
  "collection_page"
else
  "unknown"
end
blue_visible = exact_semantics_visible?(rows, "Blue Suitcase")

puts "capture_status=ok route_probe=#{route_probe} collection_row_visible=#{collection_row_visible} " \
     "collection_title_visible=#{collection_title_visible} top_right_actions=#{top_right_actions} " \
     "blue_visible=#{blue_visible} travel_archive_row_visible=#{travel_archive_row_visible} " \
     "travel_archive_title_visible=#{travel_archive_title_visible} " \
     "empty_heading_visible=#{empty_heading_visible} empty_description_visible=#{empty_description_visible}"
