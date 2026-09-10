#!/usr/bin/env bash
# bsptile-mac: sweep every display for redundant empty spaces beyond the
# single reserved spare, and remove them.
#
# purge-empty-space.sh only fires on `space_changed` -- closing the last
# window on a space you're still sitting on doesn't trigger that (you never
# left), so it never gets a chance to re-evaluate whatever spare space came
# before it. That spare is now redundant (the space you're sitting on,
# empty, effectively acts as the "next" slot instead) but nothing cleans it
# up. Fired from yabairc on `window_destroyed`, which only passes the
# (already-gone) window's id, not its former space/display -- so this just
# sweeps every display rather than targeting the one that changed.
set -uo pipefail

# yabai's own per-space window-count bookkeeping can lag slightly behind
# the window_destroyed event dispatch -- observed directly: querying
# immediately can still see the just-emptied space as "occupied," making
# whatever comes after it look like the correctly reserved spare instead
# of the redundant extra it actually is. Not latency-critical (background
# cleanup, not something the user is waiting on), so just wait it out.
sleep 0.3

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_one_extra() {
    # re-queries fresh each call rather than acting on a stale batch list --
    # removing a space renumbers the ones after it, so a list of "extra"
    # indexes computed before any removal can point at the wrong space by
    # the time a later removal in the same sweep runs.
    local display_idx="$1" last_occupied reserved
    last_occupied="$(yabai -m query --spaces | jq -r --argjson d "$display_idx" \
        '[.[] | select(.display == $d) | select((.windows | length) > 0) | .index] | max // 0')"
    reserved=$((last_occupied + 1))
    # never touch the focused space itself -- Mission Control can't remove
    # the active space anyway, and forcibly navigating the user off
    # whatever they're sitting on would be its own kind of bug.
    yabai -m query --spaces | jq -r --argjson d "$display_idx" --argjson r "$reserved" \
        '[.[] | select(.display == $d) | select((.windows | length) == 0) | select(.index != $r) | select(."has-focus" == false) | .index] | first // empty'
}

yabai -m query --displays | jq -r '.[].index' | while IFS= read -r display_idx; do
    [ -n "$display_idx" ] || continue
    attempts=0
    while [ "$attempts" -lt 10 ]; do
        extra="$(find_one_extra "$display_idx")"
        [ -n "$extra" ] || break
        "$BIN_DIR/remove-desktop.sh" "$extra"
        attempts=$((attempts + 1))
    done
done
