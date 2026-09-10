#!/usr/bin/env bash
# bsptile-mac: create a new Space via Mission Control's own "+" button.
# yabai's `space --create` needs SIP partially disabled (its scripting-
# addition); Mission Control's UI can do the same thing without that, via
# a plain AXPress action -- the sibling discovery to AXRemoveDesktop in
# purge-empty-space.sh, same technique.
#
# NOTE: untested with multiple displays -- Mission Control's Spaces Bar
# layout when "Displays have separate Spaces" spans more than one display
# hasn't been verified on real hardware. This presses whichever "+" button
# it finds first under the Dock process's "Mission Control" group, which is
# unambiguous on a single display but may not target the intended display
# on a multi-monitor setup.
#
# NOTE: callers that create several slots at once to reach a higher one
# (e.g. jumping straight to slot 5 with only 3 existing) leave any
# intermediate slots that were created but never actually focused --
# purge-empty-space.sh only evaluates a space when you *navigate away*
# from it, so a slot you passed through without visiting doesn't get that
# chance. Harmless, but can leave a stray empty space sitting there until
# something eventually visits and leaves it.
set -uo pipefail

# The Mission Control automation has been observed to occasionally not
# take effect on the first attempt (same class of flakiness as other UI
# automation in this repo -- see new-ghostty-window.sh) -- verify a space
# actually got added and retry rather than trusting a single attempt.
before_count="$(yabai -m query --spaces 2>/dev/null | jq -r 'length')"

create_once() {
    osascript -e '
tell application "Mission Control" to launch
delay 0.35
tell application "System Events"
    tell process "Dock"
        set mc to (first UI element whose role is "AXGroup" and name is "Mission Control")
        set g to item 1 of (UI elements of mc)
        set spacesBar to (first UI element of g whose name is "Spaces Bar")
        set addBtn to (first UI element of spacesBar whose role is "AXButton")
        perform action "AXPress" of addBtn
    end tell
end tell
delay 0.3
tell application "System Events" to key code 53
delay 0.4
' >/dev/null 2>&1
}

for attempt in 1 2 3; do
    create_once
    after_count="$(yabai -m query --spaces 2>/dev/null | jq -r 'length')"
    [ -n "$before_count" ] && [ -n "$after_count" ] && [ "$after_count" -gt "$before_count" ] && exit 0
done
