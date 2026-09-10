#!/usr/bin/env bash
# bsptile-mac: move the focused window to virtual-workspace slot N on its
# own display and follow it -- mirrors bsptile's Super+Shift+1..9,0.
# See space-focus.sh for the slot-resolution/creation logic and its caveats.
#
# NOTE: `yabai -m window --space` (below) also needs SIP partially disabled
# on macOS Monterey 12.7+/Ventura 13.6+/Sonoma 14.5+/Sequoia+ (per `man
# yabai`) -- a separate requirement from space creation, and still unmet
# here. This command will fail until that's addressed too; slot creation
# above it works regardless.
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

n="${1:?usage: space-move.sh <slot 1-10>}"
[ "$n" = "0" ] && n=10

display_idx=$(yabai -m query --displays --display | jq -r '.index')

# `mapfile` needs bash 4+; macOS ships bash 3.2, so read the array one line
# at a time instead.
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
    "$BIN_DIR/create-space.sh" || true
    attempts=$((attempts + 1))
    read_space_indexes
done

if [ "${#space_indexes[@]}" -lt "$n" ]; then
    echo "space-move.sh: could not create enough slots (stuck at ${#space_indexes[@]})" >&2
    exit 1
fi

target="${space_indexes[$((n - 1))]}"
yabai -m window --space "$target"

# `mission-control is active` can briefly linger after create-space.sh (or
# even an earlier, separate invocation moments before) closes it -- retry
# rather than trusting a fixed delay to always be long enough.
for i in 1 2 3 4 5; do
    yabai -m space --focus "$target" 2>/dev/null && exit 0
    sleep 0.3
done
yabai -m space --focus "$target"
