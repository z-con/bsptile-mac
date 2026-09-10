#!/usr/bin/env bash
# bsptile-mac: install/reconcile script. Safe to re-run -- sets values and
# symlinks rather than toggling/appending, same pattern as bsptile's own
# install.sh. Run from a real Terminal (not through anything non-interactive)
# since Homebrew/sudo may prompt for your password.
set -euo pipefail

if [ "$(uname)" != "Darwin" ]; then
    echo "bsptile-mac is for macOS only." >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Homebrew ---------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew not found -- installing it first."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv)"
fi

# --- packages ----------------------------------------------------------------
brew tap koekeishiya/formulae >/dev/null
brew tap FelixKratz/formulae >/dev/null

for formula in koekeishiya/formulae/yabai koekeishiya/formulae/skhd FelixKratz/formulae/borders jq; do
    brew list "$formula" &>/dev/null || brew install "$formula"
done

# --- config symlinks ----------------------------------------------------------
link() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        mv "$dest" "$dest.bak.$(date +%s)"
        echo "Backed up existing $dest"
    fi
    ln -sfn "$src" "$dest"
}

link "$REPO_DIR/yabairc" "$HOME/.yabairc"
link "$REPO_DIR/skhdrc" "$HOME/.skhdrc"
link "$REPO_DIR/bordersrc" "$HOME/.config/borders/bordersrc"

chmod +x "$REPO_DIR"/bin/*.sh "$REPO_DIR/yabairc" "$REPO_DIR/bordersrc"

# --- macOS behavior tweaks -------------------------------------------------
# Mission Control's "switch to a Space with open windows for the
# application" (on by default) fights the whole point of per-monitor
# workspaces: switch to an *empty* space and press Cmd+Return, and
# activating Ghostty auto-switches back to whatever space its other
# windows are already on before the new window is created there instead.
defaults write com.apple.dock workspaces-auto-swoosh -bool NO
killall Dock >/dev/null 2>&1 || true

# --- compiled helper app --------------------------------------------------
# ghostty-new-window.app is built fresh on each machine rather than
# committed as a binary -- osacompile ad-hoc signs it per-machine anyway.
# See bin/ghostty-new-window.applescript for why this needs to be a real
# .app bundle rather than a bare, standalone .scpt file (new-ghostty-
# window.sh runs the script inside it via `osascript`, never launches the
# bundle itself as an app).
rm -rf "$REPO_DIR/bin/ghostty-new-window.app"
osacompile -o "$REPO_DIR/bin/ghostty-new-window.app" "$REPO_DIR/bin/ghostty-new-window.applescript"
# A stable CFBundleIdentifier (osacompile doesn't set one) so macOS's TCC
# tracks this app's Automation/Accessibility grants by identity rather than
# by path -- without it, re-running this script (which recompiles the app
# fresh every time) silently invalidates prior grants and needs re-approval
# each time. NSSupportsAutomaticTermination/NSSupportsSuddenTermination:
# this app never shows a window, which otherwise makes it a target for
# macOS's automatic-termination cleanup for idle no-window apps.
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.bsptile-mac.ghostty-new-window" "$REPO_DIR/bin/ghostty-new-window.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSSupportsAutomaticTermination bool false" "$REPO_DIR/bin/ghostty-new-window.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSSupportsSuddenTermination bool false" "$REPO_DIR/bin/ghostty-new-window.app/Contents/Info.plist"
codesign --force --deep -s - "$REPO_DIR/bin/ghostty-new-window.app"

# --- start/reload services ----------------------------------------------------
# yabai and skhd manage their own launchd services (--start-service) rather
# than implementing brew's #plist/#service hooks -- `brew services restart`
# on either fails with "has not implemented #plist, #service or provided a
# locatable service file". borders is a normal brew service.
yabai --stop-service >/dev/null 2>&1 || true
yabai --start-service
skhd --stop-service >/dev/null 2>&1 || true
skhd --start-service
brew services restart borders

cat <<EOF

bsptile-mac config installed. A few things macOS/yabai require you to do by
hand -- none of this can be scripted:

1. Grant Accessibility permission to yabai and skhd:
   System Settings > Privacy & Security > Accessibility
   -> add /opt/homebrew/bin/yabai and /opt/homebrew/bin/skhd (or
      /usr/local/bin/... on Intel), enable both.
   skhd on recent macOS also needs Input Monitoring in the same pane.

2. Confirm per-display Spaces is on (it's the macOS default, but check):
   System Settings > Desktop & Dock > "Displays have separate Spaces" -> ON.
   This is what makes the per-monitor workspace keybinds (cmd+alt+1..0) work.

3. If drag-to-edge window snapping fights with yabai's tiling, turn it off:
   System Settings > Desktop & Dock > "Drag windows to screen edges to tile" -> OFF.

4. Cmd+Return (new Ghostty window) needs a one-time manual step: run the
   compiled helper once yourself, the same way skhd will run it --
     osascript "$REPO_DIR/bin/ghostty-new-window.app/Contents/Resources/Scripts/main.scpt"
   macOS will prompt to let it control "System Events" -- allow it (and
   Accessibility, if it separately asks). This can't be scripted: skhd is
   a headless daemon with no GUI app identity, so macOS has nothing to
   attribute that permission prompt to if skhd triggers it first. Running
   it yourself once, from a real Terminal, gives the compiled app's bundle
   identity that grant, and it carries over to skhd's later runs of the
   same script.

5. Optional/advanced, NOT done by this script: yabai's scripting addition
   (borderless resizing across every space, some extra window rules) requires
   partially disabling System Integrity Protection and a reboot into Recovery
   Mode. Read https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
   yourself before doing this -- it's a real security tradeoff, not a default
   this script should silently apply.

See README.md for the full feature list, keybindings, and known limitations
(the per-display workspace scripts especially -- untested on real hardware).
EOF
