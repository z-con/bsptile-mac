#!/usr/bin/env bash
# bsptile-mac: purge the given (just-left) space if it's empty,
# unless it's the single reserved "next" slot immediately after the last
# occupied space on its display -- mirrors bsptile's dynamic-workspaces
# behavior (destroy empty ones you leave, always keep exactly one spare at
# the end).
#
# This only fires on `space_changed` (see yabairc), i.e. when you navigate
# *away* from a space -- it can't catch a space that goes empty while you
# stay on it (closing your last window without switching away). That gap is
# consolidate-spare-spaces.sh's job, on `window_destroyed`.
set -uo pipefail

space_index="${1:?usage: purge-empty-space.sh <space index>}"

space_json="$(yabai -m query --spaces --space "$space_index" 2>/dev/null)"
[ -n "$space_json" ] || exit 0

# count real windows via `--query --windows`, filtered to
# `has-ax-reference == true`, rather than trusting the space's own
# `.windows` array. That array (and even `--query --windows` itself,
# without this filter) has been observed to keep zombie window records
# around indefinitely -- an app that quit or closed its last window
# without yabai's own bookkeeping ever clearing the reference. Such a
# record still appears in `--query --windows` with real-looking fields,
# but `has-ax-reference: false` (its Accessibility handle is gone) and
# `--query --windows --window <id>` can no longer find it -- without
# filtering on this, an actually-empty space looked permanently
# "occupied" to every check here and in
# ensure-spare-space.sh/consolidate-spare-spaces.sh. Note `is-visible`
# is *not* a usable substitute: it's false for any real window on a
# space that isn't currently the visible one, not just zombies.
real_window_count="$(yabai -m query --windows | jq -r --argjson s "$space_index" \
    '[.[] | select(.space == $s) | select(."has-ax-reference" == true)] | length')"
[ "$real_window_count" = "0" ] || exit 0

is_focused="$(echo "$space_json" | jq -r '."has-focus"')"
[ "$is_focused" = "false" ] || exit 0

display_idx="$(echo "$space_json" | jq -r '.display')"

# never purge the only space on a display
total_on_display="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" '[.[] | select(.display == $d)] | length')"
[ "$total_on_display" -gt 1 ] || exit 0

# reserved "next" slot: the empty space immediately after the last occupied
# space on this display. Never purge that one. "Occupied" here means real
# (has-ax-reference) windows too.
last_occupied="$(yabai -m query --windows | jq -r --argjson d "$display_idx" \
    '[.[] | select(.display == $d) | select(."has-ax-reference" == true)] | group_by(.space) | map(.[0].space) | max // 0')"
reserved=$((last_occupied + 1))
[ "$space_index" != "$reserved" ] || exit 0

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$BIN_DIR/remove-desktop.sh" "$space_index"
