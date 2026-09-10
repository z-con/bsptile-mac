#!/usr/bin/env bash
# bsptile-mac: the create-on-demand complement to purge-empty-space.sh's
# destroy-on-leave. When a new window lands on what is currently the *last*
# space on its display, that means the reserved spare slot just got used --
# create a fresh empty one after it, so there's always one ready. Triggered
# from yabairc on event=window_created.
set -uo pipefail

window_id="${1:?usage: ensure-spare-space.sh <window id>}"

window_json="$(yabai -m query --windows --window "$window_id" 2>/dev/null)"
[ -n "$window_json" ] || exit 0

space_index="$(echo "$window_json" | jq -r '.space')"
display_idx="$(echo "$window_json" | jq -r '.display')"
[ -n "$space_index" ] && [ "$space_index" != "null" ] || exit 0

max_index="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
    '[.[] | select(.display == $d) | .index] | max')"
[ "$space_index" = "$max_index" ] || exit 0

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$BIN_DIR/create-space.sh"
