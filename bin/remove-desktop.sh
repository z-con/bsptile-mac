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
# Matches "Desktop N" by yabai's own space `index`. Mission Control shows
# one Spaces Bar per display, but confirmed directly with two displays
# connected: its "Desktop N" numbering is globally consistent with
# yabai's own space index (display 2's own Spaces Bar showed "Desktop 3,
# 4, 5", not restarting at 1) -- so the label to search for never needs
# adjusting per display. What does need adjusting: the AppleScript
# used to search only the *first* display group under Mission Control's
# top-level AXGroup, so removing a space that was actually on a second
# display silently did nothing (the label was never on display 1's own
# Spaces Bar to find). Fixed by searching every display group's Spaces
# Bar for the matching label instead of assuming the first one.
set -uo pipefail

space_index="${1:?usage: remove-desktop.sh <space index>}"

# purge-empty-space.sh, ensure-spare-space.sh, and consolidate-spare-
# spaces.sh (the three callers into this and create-space.sh) have no
# coordination with each other -- if two fire close together (e.g.
# opening a window on one space while leaving another), each
# independently drives Mission Control and they race each other's own
# open/close cycles, which looks like it's stuck toggling. Serialize
# across all Mission-Control-driving operations with a shared lock rather
# than letting that happen; a second caller just waits briefly for the
# first to finish instead of racing it.
MC_LOCK="$HOME/.cache/yabai/mission_control.lock"
mkdir -p "$(dirname "$MC_LOCK")"
got_lock=0
for i in $(seq 1 20); do
    mkdir "$MC_LOCK" 2>/dev/null && { got_lock=1; break; }
    sleep 0.25
done
[ "$got_lock" = "1" ] || exit 1
trap 'rmdir "$MC_LOCK" 2>/dev/null' EXIT

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
            set target to missing value
            repeat with g in (UI elements of mc)
                try
                    set spacesBar to (first UI element of g whose name is "Spaces Bar")
                    set theList to (first UI element of spacesBar whose role is "AXList")
                    repeat with e in (UI elements of theList)
                        if name of e is ("Desktop " & spaceIndex) then set target to e
                    end repeat
                end try
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
