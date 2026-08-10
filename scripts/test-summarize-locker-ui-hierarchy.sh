#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly summarizer="$workspace_root/scripts/summarize-locker-ui-hierarchy.rb"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

assert_equal() {
    local expected=$1
    local actual=$2
    if [[ "$actual" != "$expected" ]]; then
        printf 'Expected: %s\nActual:   %s\n' "$expected" "$actual" >&2
        exit 1
    fi
}

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"enabled=true",' \
    '1,1,"enabled=true",0' \
    '2,2,"bounds=[0,0][1080,128]; enabled=true",1' \
    '3,2,"bounds=[0,0][1080,2340]; enabled=true",1' \
    '4,3,"clickable=true; bounds=[800,180][940,320]; enabled=true",3' \
    '5,3,"text=seeded-android-proof-test@example.org; accessibilityText=Locker-test!Aa1; bounds=[40,400][900,520]",3' \
    '6,3,"bounds=[0,0][2000,5000]; enabled=true",3' \
    '7,3,"text=Home Inventory\n2 items; accessibilityText=Home Inventory\n2 items; bounds=[40,500][900,620]",3' \
    '8,4,"text=Home Inventory; bounds=[40,500][500,560]",7' \
    > "$temp_dir/all-collections.csv"
expected='capture_status=ok route_probe=all_collections collection_row_visible=true collection_title_visible=true top_right_actions=1 blue_visible=false'
actual=$(ruby "$summarizer" "$temp_dir/all-collections.csv")
assert_equal "$expected" "$actual"

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"bounds=[0,0][1080,2340]; enabled=true",' \
    '1,1,"clickable=true; bounds=[660,180][800,320]; enabled=true",0' \
    '2,1,"clickable=true; bounds=[800,180][940,320]; enabled=true",0' \
    '3,1,"text=Blue Suitcase; accessibilityText=Blue Suitcase; bounds=[80,500][900,620]",0' \
    '4,1,"text=Home Inventory; accessibilityText=Home Inventory; bounds=[80,320][900,440]",0' \
    > "$temp_dir/collection-page.csv"
expected='capture_status=ok route_probe=collection_page collection_row_visible=false collection_title_visible=true top_right_actions=2 blue_visible=true'
actual=$(ruby "$summarizer" "$temp_dir/collection-page.csv")
assert_equal "$expected" "$actual"

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"bounds=[0,0][1080,2340]; enabled=true",' \
    '1,1,"clickable=true; bounds=[800,180][940,320]; enabled=true",0' \
    '2,2,"clickable=true; bounds=[800,180][940,320]; enabled=true",1' \
    '3,1,"clickable=true; bounds=[640,180][760,320]; enabled=true",0' \
    '4,1,"clickable=true; bounds=[560,180][620,320]; enabled=true",0' \
    > "$temp_dir/unknown.csv"
expected='capture_status=ok route_probe=unknown collection_row_visible=false collection_title_visible=false top_right_actions=3 blue_visible=false'
actual=$(ruby "$summarizer" "$temp_dir/unknown.csv")
assert_equal "$expected" "$actual"

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"enabled=true",' \
    > "$temp_dir/missing-root.csv"
if ruby "$summarizer" "$temp_dir/missing-root.csv" > /dev/null 2>&1; then
    echo "Expected a hierarchy without a bounded top-level window to fail" >&2
    exit 1
fi

printf '%s\n' \
    'element_num,depth,attributes,parent_num' \
    '0,0,"enabled=true",' \
    '1,1,"bounds=[0,0][1080,2340]; enabled=true",0' \
    '2,1,"bounds=[10,0][1090,2340]; enabled=true",0' \
    > "$temp_dir/ambiguous-viewport.csv"
if ruby "$summarizer" "$temp_dir/ambiguous-viewport.csv" > /dev/null 2>&1; then
    echo "Expected conflicting largest top-level windows to fail" >&2
    exit 1
fi

if grep --quiet --extended-regexp 'seeded-android-proof-test@example\.org|Locker-test!Aa1' \
    <(ruby "$summarizer" "$temp_dir/all-collections.csv"); then
    echo "The hierarchy summary leaked raw UI text" >&2
    exit 1
fi

echo "Locker UI hierarchy summary tests passed"
