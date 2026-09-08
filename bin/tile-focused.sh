#!/usr/bin/env bash
# bsptile-mac: pull the focused window into the tiled layout, even if it's
# currently floating -- mirrors bsptile's Super+T.
set -euo pipefail

is_floating=$(yabai -m query --windows --window | jq -r '."is-floating"')

if [ "$is_floating" = "true" ]; then
    yabai -m window --toggle float
    yabai -m window --grid 1:1:0:0:1:1 2>/dev/null || true
fi
