#!/usr/bin/env ruby

require "csv"
require "set"

abort("Usage: summarize-locker-ui-hierarchy.rb <compact-hierarchy.csv>") unless ARGV.length == 1

rows = CSV.read(ARGV.fetch(0), headers: true)
abort("Compact hierarchy is missing the attributes column") unless rows.headers&.include?("attributes")

root_bounds = rows.each_with_object([]) do |row, values|
  next unless row.fetch("depth").to_s == "0"

  match = row.fetch("attributes").to_s.match(/bounds=\[(\d+),(\d+)\]\[(\d+),(\d+)\]/)
  values << match.captures.map(&:to_i) if match
end
abort("Compact hierarchy must contain exactly one bounded root") unless root_bounds.length == 1

screen_left, screen_top, screen_right, screen_bottom = root_bounds.fetch(0)
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

puts "route_probe=#{route_probe} top_right_actions=#{top_right_actions} blue_visible=#{blue_visible}"
