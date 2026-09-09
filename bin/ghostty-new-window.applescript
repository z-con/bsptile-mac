-- bsptile-mac: compiled into ghostty-new-window.app by install.sh.
-- Sends Ghostty's own New Window keybind (cmd+n) to the running instance.
-- Must be a real .app, not a bare `osascript` call: skhd is a headless
-- background daemon with no GUI app identity, so macOS has no owner to
-- attribute a System Events Automation-permission prompt to and the
-- request is silently denied. A compiled applet has its own bundle
-- identity, so launching it once manually (see README) gets its own
-- prompt, and that grant carries over when skhd later launches the same
-- .app via `open -a`.
tell application "Ghostty" to activate
delay 0.3
tell application "System Events" to keystroke "n" using command down
