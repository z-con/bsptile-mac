use framework "Foundation"
use scripting additions

-- bsptile-mac: compiled into ghostty-new-window.app by install.sh, and run
-- via `osascript .../ghostty-new-window.app/Contents/Resources/Scripts/
-- main.scpt` (see new-ghostty-window.sh) -- never launched as a standalone
-- app via `open -a`, which spins up a full NSApplication with no window of
-- its own and made it a target for macOS's automatic-termination cleanup
-- for idle no-window apps (observed directly killing it mid-script, before
-- the delay/keystroke below ever ran).
--
-- Still needs to live inside a real .app bundle with a stable
-- CFBundleIdentifier (see install.sh), not a bare .scpt file: skhd is a
-- headless daemon with no GUI app identity, so macOS has no owner to
-- attribute a System Events Automation-permission prompt to and the
-- request is silently denied -- but running the script inside a bundle
-- with its own stable identity, once, from a real Terminal (see README),
-- gets that bundle its own grant, which carries over when skhd later runs
-- the same script the same way.
--
-- Takes the id of the window that should anchor the bsp split as its one
-- argument (new-ghostty-window.sh passes it as an osascript argument).
-- Launching *this* script at all -- even via osascript, with no window of
-- its own -- is itself what knocks yabai's focus off whatever was focused
-- a moment ago in the calling shell script (observed: re-asserting focus
-- from the shell script, before this runs, does not stick; the new window
-- still ends up splitting off some other, unrelated pane). So re-assert it
-- here, as late as possible, right before the keystroke that actually
-- creates the new window.
on run argv
    -- This app has no window of its own, which makes it a target for
    -- macOS's automatic-termination cleanup for idle no-window apps --
    -- observed to actually kill it mid-script, before the delay/keystroke
    -- below ever run. The Info.plist NSSupportsAutomaticTermination/
    -- NSSupportsSuddenTermination keys don't reliably prevent this (AppKit
    -- re-toggles termination eligibility itself during startup); calling
    -- disableAutomaticTermination directly is the documented, authoritative
    -- way to hold it off.
    try
        (current application's NSProcessInfo's processInfo())'s disableAutomaticTermination:"opening a new window"
    end try

    set anchorId to ""
    if (count of argv) > 0 then set anchorId to item 1 of argv
    tell application "Ghostty" to activate
    if anchorId is not "" then
        try
            do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:$PATH yabai -m window --focus " & anchorId & " >/dev/null 2>&1"
        end try
    end if
    delay 0.3
    tell application "System Events" to keystroke "n" using command down
end run
