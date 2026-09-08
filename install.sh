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

# --- start/reload services ----------------------------------------------------
brew services restart yabai
brew services restart skhd
brew services restart borders

cat <<'EOF'

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

4. Optional/advanced, NOT done by this script: yabai's scripting addition
   (borderless resizing across every space, some extra window rules) requires
   partially disabling System Integrity Protection and a reboot into Recovery
   Mode. Read https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
   yourself before doing this -- it's a real security tradeoff, not a default
   this script should silently apply.

See README.md for the full feature list, keybindings, and known limitations
(the per-display workspace scripts especially -- untested on real hardware).
EOF
