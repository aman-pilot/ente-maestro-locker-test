#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly summarizer="$workspace_root/scripts/summarize-locker-ui-hierarchy.rb"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"bounds=[0,0][1080,2340]; enabled=true",' \
    '1,1,"clickable=true; bounds=[800,180][940,320]; enabled=true",0' \
    '2,1,"text=seeded-android-proof-test@example.org; accessibilityText=Locker-test!Aa1; bounds=[40,400][900,520]",0' \
    '3,1,"bounds=[0,0][2000,5000]; enabled=true",0' \
    > "$temp_dir/all-collections.csv"
expected='route_probe=all_collections top_right_actions=1 blue_visible=false'
actual=$(ruby "$summarizer" "$temp_dir/all-collections.csv")
[[ "$actual" == "$expected" ]]

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"bounds=[0,0][1080,2340]; enabled=true",' \
    '1,1,"clickable=true; bounds=[660,180][800,320]; enabled=true",0' \
    '2,1,"clickable=true; bounds=[800,180][940,320]; enabled=true",0' \
    '3,1,"text=Blue Suitcase; accessibilityText=Blue Suitcase; bounds=[80,500][900,620]",0' \
    > "$temp_dir/collection-page.csv"
expected='route_probe=collection_page top_right_actions=2 blue_visible=true'
actual=$(ruby "$summarizer" "$temp_dir/collection-page.csv")
[[ "$actual" == "$expected" ]]

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"bounds=[0,0][1080,2340]; enabled=true",' \
    '1,1,"clickable=true; bounds=[800,180][940,320]; enabled=true",0' \
    '2,2,"clickable=true; bounds=[800,180][940,320]; enabled=true",1' \
    '3,1,"clickable=true; bounds=[640,180][760,320]; enabled=true",0' \
    '4,1,"clickable=true; bounds=[520,180][620,320]; enabled=true",0' \
    > "$temp_dir/unknown.csv"
expected='route_probe=unknown top_right_actions=3 blue_visible=false'
actual=$(ruby "$summarizer" "$temp_dir/unknown.csv")
[[ "$actual" == "$expected" ]]

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,1,"bounds=[0,0][1080,2340]; enabled=true",' \
    > "$temp_dir/missing-root.csv"
if ruby "$summarizer" "$temp_dir/missing-root.csv" > /dev/null 2>&1; then
    echo "Expected a hierarchy without one bounded root to fail" >&2
    exit 1
fi

if grep --quiet --extended-regexp 'seeded-android-proof-test@example\.org|Locker-test!Aa1' \
    <(ruby "$summarizer" "$temp_dir/all-collections.csv"); then
    echo "The hierarchy summary leaked raw UI text" >&2
    exit 1
fi

echo "Locker UI hierarchy summary tests passed"
