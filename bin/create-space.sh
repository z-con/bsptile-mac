#!/usr/bin/env bash
# bsptile-mac: create a new Space on the given display, via Mission
# Control's own "+" button. yabai's `space --create` needs SIP partially
# disabled (its scripting-addition); Mission Control's UI can do the same
# thing without that, via a plain AXPress action -- the sibling discovery
# to AXRemoveDesktop in remove-desktop.sh, same technique.
#
# Takes the index of any *existing* space already on the target display
# (an "anchor") rather than a display index directly: Mission Control
# shows one Spaces Bar per display, and confirmed directly with two
# displays connected, its "Desktop N" labels are numbered globally
# consistent with yabai's own space index (not restarting at 1 per
# display) -- so finding the Spaces Bar that contains "Desktop <anchor>"
# reliably identifies the right display's "+" button to press, without
# needing yabai's own display index to line up with anything in Mission
# Control's own UI. An earlier version of this pressed whichever "+"
# button it found first under the Dock process's "Mission Control" group
# unconditionally -- worked by luck on a single display, but silently
# created the space on the wrong display whenever the caller actually
# wanted a second one.
#
# NOTE: callers that create several slots at once to reach a higher one
# (e.g. jumping straight to slot 5 with only 3 existing) leave any
# intermediate slots that were created but never actually focused --
# purge-empty-space.sh only evaluates a space when you *navigate away*
# from it, so a slot you passed through without visiting doesn't get that
# chance. Harmless, but can leave a stray empty space sitting there until
# something eventually visits and leaves it.
set -uo pipefail

anchor_space="${1:?usage: create-space.sh <existing space index on the target display>}"

# purge-empty-space.sh, ensure-spare-space.sh, and consolidate-spare-
# spaces.sh (the three callers into this and remove-desktop.sh) have no
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

# The Mission Control automation has been observed to occasionally not
# take effect on the first attempt (same class of flakiness as other UI
# automation in this repo -- see new-ghostty-window.sh) -- verify a space
# actually got added and retry rather than trusting a single attempt.
before_count="$(yabai -m query --spaces 2>/dev/null | jq -r 'length')"

create_once() {
    osascript -e '
on run argv
    set anchorSpace to item 1 of argv
    tell application "Mission Control" to launch
    delay 0.35
    tell application "System Events"
        tell process "Dock"
            set mc to (first UI element whose role is "AXGroup" and name is "Mission Control")
            set targetGroup to missing value
            repeat with g in (UI elements of mc)
                try
                    set spacesBar to (first UI element of g whose name is "Spaces Bar")
                    set theList to (first UI element of spacesBar whose role is "AXList")
                    repeat with e in (UI elements of theList)
                        if name of e is ("Desktop " & anchorSpace) then set targetGroup to g
                    end repeat
                end try
            end repeat
            if targetGroup is not missing value then
                set spacesBar to (first UI element of targetGroup whose name is "Spaces Bar")
                set addBtn to (first UI element of spacesBar whose role is "AXButton")
                perform action "AXPress" of addBtn
            end if
        end tell
    end tell
    delay 0.3
    tell application "System Events" to key code 53
    delay 0.4
end run
' "$anchor_space" >/dev/null 2>&1
}

for attempt in 1 2 3; do
    create_once
    after_count="$(yabai -m query --spaces 2>/dev/null | jq -r 'length')"
    [ -n "$before_count" ] && [ -n "$after_count" ] && [ "$after_count" -gt "$before_count" ] && exit 0
done
