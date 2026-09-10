#!/usr/bin/env bash
# bsptile-mac: remove the given Space via Mission Control's own per-Desktop
# "remove" action. Pure mechanism, no policy -- see purge-empty-space.sh and
# consolidate-spare-spaces.sh for the two callers that decide *when* a space
# should be removed.
#
# yabai's own `space --destroy` needs SIP partially disabled (its
# scripting-addition) -- declined for this machine. Mission Control's own
# UI can remove a Space without that, via a real Accessibility action
# (AXRemoveDesktop) exposed directly on each Desktop-N button in its Spaces
# Bar -- no hover/coordinate-click simulation needed. The real cost is
# visual: this briefly opens and closes Mission Control on screen, and in
# one test run (out of several) a transient window flashed and self-closed
# a few seconds later during the transition -- not reproduced on retest,
# cause unconfirmed.
#
# CAVEAT: matches "Desktop N" by yabai's own space `index`, which is a
# single global ordering across every display. Mission Control numbers
# Desktops per-display in its Spaces Bar, so this mapping only holds on a
# single-display setup -- untested with multiple displays.
set -uo pipefail

space_index="${1:?usage: remove-desktop.sh <space index>}"

# `index` is positional (shifts when other spaces are added/removed around
# it); `id` is this space's own stable identifier, unaffected by that --
# use it to verify the removal actually landed, since the Mission Control
# automation has been observed to occasionally not take effect on the
# first attempt (same class of flakiness as other UI-automation timing in
# this repo -- see new-ghostty-window.sh).
target_id="$(yabai -m query --spaces --space "$space_index" 2>/dev/null | jq -r '.id')"
[ -n "$target_id" ] && [ "$target_id" != "null" ] || exit 0

remove_once() {
    osascript -e '
on run argv
    set spaceIndex to item 1 of argv
    tell application "Mission Control" to launch
    delay 0.35
    tell application "System Events"
        tell process "Dock"
            set mc to (first UI element whose role is "AXGroup" and name is "Mission Control")
            set g to item 1 of (UI elements of mc)
            set spacesBar to (first UI element of g whose name is "Spaces Bar")
            set theList to (first UI element of spacesBar whose role is "AXList")
            set target to missing value
            repeat with e in (UI elements of theList)
                if name of e is ("Desktop " & spaceIndex) then set target to e
            end repeat
            if target is not missing value then
                perform action "AXRemoveDesktop" of target
            end if
        end tell
    end tell
    delay 0.15
    tell application "System Events" to key code 53
    delay 0.4
end run
' "$space_index" >/dev/null 2>&1
}

still_there() {
    yabai -m query --spaces 2>/dev/null | jq -e --argjson id "$target_id" 'any(.[]; .id == $id)' >/dev/null 2>&1
}

for attempt in 1 2 3; do
    still_there || exit 0
    # re-resolve the current index each attempt -- an earlier failed
    # attempt could still have shifted other spaces around, or the space
    # itself may have moved if the user navigated in the meantime.
    space_index="$(yabai -m query --spaces 2>/dev/null | jq -r --argjson id "$target_id" '.[] | select(.id == $id) | .index')"
    [ -n "$space_index" ] && [ "$space_index" != "null" ] || exit 0
    remove_once
done
