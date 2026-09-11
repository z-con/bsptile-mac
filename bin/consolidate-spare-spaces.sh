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
    #
    # "occupied" is computed via `--query --windows`, filtered to
    # `has-ax-reference == true`, rather than trusting a space's own
    # `.windows` array (or even the unfiltered window list). A zombie
    # window record -- an app that quit or closed its last window
    # without yabai's own bookkeeping ever clearing the reference --
    # keeps appearing there indefinitely with `has-ax-reference: false`,
    # which made an actually-empty space look permanently "occupied" and
    # never get cleaned up. `is-visible` is *not* a usable substitute for
    # this: it's false for any real window on a space that isn't
    # currently the visible one, not just zombies.
    local display_idx="$1" last_occupied reserved occupied_spaces
    last_occupied="$(yabai -m query --windows | jq -r --argjson d "$display_idx" \
        '[.[] | select(.display == $d) | select(."has-ax-reference" == true)] | group_by(.space) | map(.[0].space) | max // 0')"
    reserved=$((last_occupied + 1))
    occupied_spaces="$(yabai -m query --windows | jq -c --argjson d "$display_idx" \
        '[.[] | select(.display == $d) | select(."has-ax-reference" == true) | .space] | unique')"
    # never touch the focused space itself -- Mission Control can't remove
    # the active space anyway, and forcibly navigating the user off
    # whatever they're sitting on would be its own kind of bug.
    yabai -m query --spaces | jq -r --argjson d "$display_idx" --argjson r "$reserved" --argjson occ "$occupied_spaces" \
        '[.[] | select(.display == $d) | . as $space | select($occ | index($space.index) | not) | select($space.index != $r) | select($space."has-focus" == false) | $space.index] | first // empty'
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
