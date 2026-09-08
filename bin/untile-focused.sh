#!/usr/bin/env bash
# bsptile-mac: untile the focused window, leaving it floating where it was --
# mirrors bsptile's Super+Shift+T. Its sibling reclaims the space via yabai's
# own bsp reflow, same as the GNOME extension.
set -euo pipefail

is_floating=$(yabai -m query --windows --window | jq -r '."is-floating"')

if [ "$is_floating" = "false" ]; then
    yabai -m window --toggle float
fi
