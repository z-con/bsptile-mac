#!/usr/bin/env bash
# bsptile-mac: open a new Ghostty window without spawning a new process.
# `open -na Ghostty` (the naive approach) launches a whole new instance every
# time, which piles up in the Dock and doesn't go away when its window is
# closed with Cmd+W -- only Cmd+Q actually quits each spawned process.
# Ghostty has no macOS IPC "new window" action (`ghostty +new-window` errors
# as unsupported on this platform), so instead activate the existing
# instance and simulate its own New Window keybind (cmd+n) via the compiled
# ghostty-new-window.app (see ghostty-new-window.applescript for why this
# has to be a real .app rather than a bare `osascript` call -- skhd is a
# headless daemon with no GUI identity for macOS to attribute the required
# System Events Automation permission to).
#
# NOTE: don't use `pgrep` to check whether Ghostty is already running --
# it's unreliable in this environment (observed to flake on an exact,
# verified-correct pattern from one invocation to the next). yabai's window
# list has been solid throughout, so use that instead.
#
# Run the compiled script *through osascript*, pointed at the .scpt file
# inside the bundle -- not `open -a` launching the .app itself as a
# standalone process. The latter spins up a full NSApplication with no
# window of its own, which makes it a target for macOS's automatic-
# termination cleanup for idle no-window apps; observed directly (with
# `log show --predicate 'process == "applet"'`) killing it mid-script,
# before the delay/keystroke below ever ran, and later just hanging
# indefinitely instead once termination was suppressed. Running the exact
# same compiled script via `osascript path/to/main.scpt` never spins up
# that lifecycle at all and was reliable in every test. The script still
# needs to live inside a real .app bundle with a stable CFBundleIdentifier
# (set by install.sh after compiling) rather than as a bare .scpt file --
# macOS's TCC attributes permission to the containing bundle even when
# invoked this way, and a bare, identity-less .scpt didn't get a stable
# grant across rebuilds.
#
# The applet's activation + synthetic keystroke are asynchronous and
# occasionally don't land (the keystroke can fire before Ghostty is truly
# frontmost), and a naive window-count comparison taken immediately
# afterwards can race with yabai's own internal state settling. Compare the
# actual window ID *set* before/after, and require the new id to still be
# present after a short settle period before declaring success, retrying a
# few times otherwise. Poll for a while rather than checking once: a single
# fixed sleep before giving up and retrying can mistake a merely-slow
# attempt for a failed one, and the retry's own keystroke then lands on top
# of the first one's, opening two windows for one keypress.
#
# Where the window actually lands is Ghostty's own call (it tends to place
# it near its last-used window), which is *not* necessarily whatever
# display currently has focus -- so once we have the new window's id, pin
# it onto the display that was focused when this script started, rather
# than trusting wherever Ghostty put it. Only do this when it's actually on
# the wrong display: `--display` reparents the window into a default
# position in that display's bsp tree, which knocks it out of the natural
# insertion point (next to the window that was focused) even when it's
# already on the right display -- e.g. a 3rd window landing back on the
# left instead of splitting off the right-hand focused window.
#
# Separately: bsp insertion also anchors to whichever window yabai
# considers focused *at the moment the new window is created*, and just
# launching ghostty-new-window.app -- even though it has no window of its
# own -- is itself enough to knock yabai's focus off of whatever was
# focused a moment ago (observed directly: re-asserting focus here, before
# `open -a` runs, does not survive it; the new window still ends up
# splitting off some other, unrelated pane). So pass the intended anchor
# into the applet itself via --args, and it re-asserts focus internally,
# right before the keystroke that actually creates the window -- as late
# as possible, after whatever launching it disturbs has already happened.
set -uo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ghostty_window_ids() {
    yabai -m query --windows 2>/dev/null | jq -r '.[] | select(.app == "Ghostty") | .id' | sort -n
}

target_display="$(yabai -m query --displays --display 2>/dev/null | jq -r '.index')"
anchor="$(yabai -m query --windows --window 2>/dev/null | jq -r '.id')"
before="$(ghostty_window_ids)"

if [ -z "$before" ]; then
    # no existing window means no running instance to hand off to -- a
    # plain launch creates its own initial window.
    open -a Ghostty
    exit 0
fi

SCRIPT="$BIN_DIR/ghostty-new-window.app/Contents/Resources/Scripts/main.scpt"

for attempt in 1 2 3 4 5; do
    if [ -n "$anchor" ] && [ "$anchor" != "null" ]; then
        osascript "$SCRIPT" "$anchor" >/dev/null 2>&1
    else
        osascript "$SCRIPT" >/dev/null 2>&1
    fi
    new_id=""
    for poll in 1 2 3 4 5 6 7 8; do
        sleep 0.3
        after="$(ghostty_window_ids)"
        # tail -n1: if the previous attempt's keystroke was only slow (not
        # failed) and lands in the same window it opened here too, this
        # picks the most recent one rather than acting on both.
        candidate="$(comm -13 <(echo "$before") <(echo "$after") | tail -n1)"
        if [ -n "$candidate" ]; then
            new_id="$candidate"
            break
        fi
    done
    if [ -n "$new_id" ]; then
        sleep 0.4
        settled="$(ghostty_window_ids)"
        if echo "$settled" | grep -qx "$new_id"; then
            if [ -n "$target_display" ]; then
                actual_display="$(yabai -m query --windows --window "$new_id" 2>/dev/null | jq -r '.display')"
                if [ "$actual_display" != "$target_display" ]; then
                    yabai -m window "$new_id" --display "$target_display" 2>/dev/null
                fi
            fi
            yabai -m window --focus "$new_id" 2>/dev/null
            exit 0
        fi
    fi
done
exit 1
