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
# Slot creation goes through create-space.sh (Mission Control's own "+"
# button via Accessibility) rather than `yabai -m space --create`, which
# needs SIP partially disabled -- see that script for how it targets the
# right display.
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

n="${1:?usage: space-focus.sh <slot 1-10>}"
[ "$n" = "0" ] && n=10

display_idx=$(yabai -m query --displays --display | jq -r '.index')

# spaces on this display, in on-screen order. `mapfile` needs bash 4+;
# macOS ships bash 3.2, so read into the array one line at a time instead.
read_space_indexes() {
    space_indexes=()
    while IFS= read -r idx; do
        space_indexes+=("$idx")
    done < <(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
        '[.[] | select(.display == $d)] | sort_by(.index) | .[].index')
}
read_space_indexes

attempts=0
while [ "${#space_indexes[@]}" -lt "$n" ] && [ "$attempts" -lt 10 ]; do
    # create-space.sh needs an existing space already on the target
    # display to find the right Mission Control group to act on -- the
    # last (highest-index) one already on this display works.
    anchor="${space_indexes[$((${#space_indexes[@]} - 1))]}"
    "$BIN_DIR/create-space.sh" "$anchor" || true
    attempts=$((attempts + 1))
    read_space_indexes
done

if [ "${#space_indexes[@]}" -lt "$n" ]; then
    echo "space-focus.sh: could not create enough slots (stuck at ${#space_indexes[@]})" >&2
    exit 1
fi

target="${space_indexes[$((n - 1))]}"

# `mission-control is active` can briefly linger after create-space.sh (or
# even an earlier, separate invocation moments before) closes it -- retry
# rather than trusting a fixed delay to always be long enough.
for i in 1 2 3 4 5; do
    yabai -m space --focus "$target" 2>/dev/null && exit 0
    sleep 0.3
done
yabai -m space --focus "$target"
