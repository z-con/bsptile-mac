#!/usr/bin/env bash
# bsptile-mac: jump directly to virtual-workspace slot N on the currently
# focused display, without creating new slots. If N is beyond however many
# slots currently exist, land on the last one (the spare) instead of
# creating empty slots up to N.
#
# Companion to space-focus.sh, which *does* create slots on demand -- this
# one deliberately never does (see `cmd-1..0` vs `cmd+alt-1..0` in skhdrc).
set -euo pipefail

n="${1:?usage: space-goto.sh <slot 1-10>}"
[ "$n" = "0" ] && n=10

display_idx=$(yabai -m query --displays --display | jq -r '.index')

# `mapfile` needs bash 4+; macOS ships bash 3.2, so read the array one line
# at a time instead.
space_indexes=()
while IFS= read -r idx; do
    space_indexes+=("$idx")
done < <(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
    '[.[] | select(.display == $d)] | sort_by(.index) | .[].index')

count="${#space_indexes[@]}"
[ "$count" -gt 0 ] || exit 0
[ "$n" -le "$count" ] || n="$count"

target="${space_indexes[$((n - 1))]}"

# `mission-control is active` can briefly linger after a nearby create/
# purge signal closes it -- retry rather than trusting a fixed delay to
# always be long enough (see space-focus.sh).
for i in 1 2 3 4 5; do
    yabai -m space --focus "$target" 2>/dev/null && exit 0
    sleep 0.3
done
yabai -m space --focus "$target"
