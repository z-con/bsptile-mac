#!/usr/bin/env bash
# bsptile-mac: the create-on-demand complement to purge-empty-space.sh's
# destroy-on-leave. When a new window lands on what is currently the *last*
# space on its display, that means the reserved spare slot just got used --
# create a fresh empty one after it, so there's always one ready. Triggered
# from yabairc on event=window_created.
set -uo pipefail

window_id="${1:?usage: ensure-spare-space.sh <window id>}"

# yabai's own window metadata (which display/space a brand-new window
# landed on) can be momentarily unsettled right at the instant
# window_created fires -- observed directly: a manual, slightly-delayed
# invocation of this same check always found the right answer, but the
# real-time signal occasionally computed a stale display/space and
# concluded (wrongly) that nothing needed to happen. Retry the whole
# check a few times rather than trusting a single, immediate read.
for attempt in 1 2 3 4 5; do
    window_json="$(yabai -m query --windows --window "$window_id" 2>/dev/null)"
    [ -n "$window_json" ] || exit 0

    space_index="$(echo "$window_json" | jq -r '.space')"
    display_idx="$(echo "$window_json" | jq -r '.display')"
    [ -n "$space_index" ] && [ "$space_index" != "null" ] || exit 0

    max_index="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
        '[.[] | select(.display == $d) | .index] | max')"

    if [ "$space_index" = "$max_index" ]; then
        BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        "$BIN_DIR/create-space.sh" "$space_index"
        exit 0
    fi
    sleep 0.3
done
