#!/usr/bin/env bash
# bsptile-mac: move the focused window to virtual-workspace slot N on its
# own display and follow it -- mirrors bsptile's Super+Shift+1..9,0.
# See space-focus.sh for the slot-resolution/creation logic and its caveats.
set -euo pipefail

n="${1:?usage: space-move.sh <slot 1-10>}"
[ "$n" = "0" ] && n=10

display_idx=$(yabai -m query --displays --display | jq -r '.index')

mapfile -t space_indexes < <(
    yabai -m query --spaces | jq -r --argjson d "$display_idx" \
        '[.[] | select(.display == $d)] | sort_by(.index) | .[].index'
)

while [ "${#space_indexes[@]}" -lt "$n" ]; do
    yabai -m space --create "$display_idx" 2>/dev/null \
        || { yabai -m space --create; yabai -m space last --display "$display_idx"; }
    mapfile -t space_indexes < <(
        yabai -m query --spaces | jq -r --argjson d "$display_idx" \
            '[.[] | select(.display == $d)] | sort_by(.index) | .[].index'
    )
done

target="${space_indexes[$((n - 1))]}"
yabai -m window --space "$target"
yabai -m space --focus "$target"
