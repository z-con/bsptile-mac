#!/usr/bin/env bash
# bsptile-mac: open a new Ghostty window without spawning a new process.
# `open -na Ghostty` (the naive approach) launches a whole new instance every
# time, which piles up in the Dock and doesn't go away when its window is
# closed with Cmd+W -- only Cmd+Q actually quits each spawned process.
# Ghostty has no macOS IPC "new window" action (`ghostty +new-window` errors
# as unsupported on this platform), so instead activate the existing
# instance and simulate its own New Window keybind (cmd+n).
#
# NOTE: don't use `pgrep` to check whether Ghostty is already running --
# it's unreliable in this environment (observed to flake on an exact,
# verified-correct pattern from one invocation to the next). yabai's window
# list has been solid throughout, so use that instead.
#
# Both `open -a` activation and the synthetic keystroke are asynchronous and
# occasionally don't land (the keystroke can fire before Ghostty is truly
# frontmost), and a naive window-count comparison taken immediately
# afterwards can race with yabai's own internal state settling. Compare the
# actual window ID *set* before/after, and require the new id to still be
# present after a short settle period before declaring success, retrying a
# few times otherwise.
set -uo pipefail

ghostty_window_ids() {
    yabai -m query --windows 2>/dev/null | jq -r '.[] | select(.app == "Ghostty") | .id' | sort -n
}

before="$(ghostty_window_ids)"

if [ -z "$before" ]; then
    # no existing window means no running instance to hand off to -- a
    # plain launch creates its own initial window.
    open -a Ghostty
    exit 0
fi

for attempt in 1 2 3 4 5; do
    open -a Ghostty
    sleep 0.4
    osascript -e 'tell application "System Events" to keystroke "n" using command down' >/dev/null 2>&1
    sleep 0.4
    after="$(ghostty_window_ids)"
    new_id="$(comm -13 <(echo "$before") <(echo "$after"))"
    if [ -n "$new_id" ]; then
        sleep 0.4
        settled="$(ghostty_window_ids)"
        if echo "$settled" | grep -qx "$new_id"; then
            exit 0
        fi
    fi
done
exit 1
