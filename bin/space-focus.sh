#!/usr/bin/env bash
# bsptile-mac: focus virtual-workspace slot N *on the currently focused
# display* -- mirrors bsptile's per-monitor-workspaces Super+1..9,0.
#
# Unlike bsptile (which had to simulate this in GJS because Mutter has no
# native per-monitor workspace concept), macOS + yabai give you this for
# free via "Displays have separate Spaces" (on by default). This script
# just resolves "slot N on this display" to the right global space index
# and creates slots on demand, matching bsptile's dynamic-growing-slots
# behavior.
#
# NOTE: untested on real hardware -- I don't have a Mac to run yabai on.
# yabai's exact `space --create` display-targeting syntax has changed
# across versions; verify this against your installed yabai's `man yabai`
# if a slot fails to create, and see README.md's Known limitations.
set -euo pipefail

n="${1:?usage: space-focus.sh <slot 1-10>}"
[ "$n" = "0" ] && n=10

display_idx=$(yabai -m query --displays --display | jq -r '.index')

# spaces on this display, in on-screen order
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
yabai -m space --focus "$target"
