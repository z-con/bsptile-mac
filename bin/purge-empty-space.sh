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

window_count="$(echo "$space_json" | jq -r '.windows | length')"
[ "$window_count" = "0" ] || exit 0

is_focused="$(echo "$space_json" | jq -r '."has-focus"')"
[ "$is_focused" = "false" ] || exit 0

display_idx="$(echo "$space_json" | jq -r '.display')"

# never purge the only space on a display
total_on_display="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" '[.[] | select(.display == $d)] | length')"
[ "$total_on_display" -gt 1 ] || exit 0

# reserved "next" slot: the empty space immediately after the last occupied
# space on this display. Never purge that one.
last_occupied="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
    '[.[] | select(.display == $d) | select((.windows | length) > 0) | .index] | max // 0')"
reserved=$((last_occupied + 1))
[ "$space_index" != "$reserved" ] || exit 0

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$BIN_DIR/remove-desktop.sh" "$space_index"
