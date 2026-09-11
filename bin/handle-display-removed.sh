#!/usr/bin/env bash
# bsptile-mac: when an external monitor disconnects, switch to space 1 on
# monitor 1 -- macOS's own merge-on-disconnect drops the disconnected
# display's windows there, so this just makes sure you're looking at
# where they actually landed instead of wherever you happened to be
# working.
#
# Deliberately just this: no attempt to control *where* the windows land
# (that's up to macOS, not something this fights), no dragging, no
# Mission Control automation. Two earlier, more ambitious versions of
# this tried to actively redistribute the windows -- onto freshly created
# spaces preserving their original groupings, and later onto the single
# spare space -- both via synthetic drag-and-hold automation. Both worked
# in solo testing; the first was unusably slow and visually chaotic on
# real hardware, and the second, while much lighter, still wasn't the
# experience wanted. This version has no automation to go wrong at all.
set -uo pipefail

TARGET_DISPLAY=1

target_space="$(yabai -m query --spaces | jq -r --argjson d "$TARGET_DISPLAY" \
    '[.[] | select(.display == $d)] | sort_by(.index) | first | .index // empty')"
[ -n "$target_space" ] || exit 0

# `mission-control is active` can briefly linger from unrelated recent
# activity (see space-focus.sh/space-goto.sh for the same pattern) --
# retry rather than trusting a single attempt.
for i in 1 2 3 4 5; do
    yabai -m space --focus "$target_space" 2>/dev/null && exit 0
    sleep 0.3
done
