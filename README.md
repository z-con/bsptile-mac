# bsptile-mac

A port of [bsptile](https://github.com/z-con/bsptile) (a GNOME Shell
extension implementing i3/Hyprland-style BSP auto-tiling) to macOS, built on
top of [yabai](https://github.com/koekeishiya/yabai) as the tiling
foundation, [skhd](https://github.com/koekeishiya/skhd) for keybindings, and
[JankyBorders](https://github.com/FelixKratz/JankyBorders) for the focus
border. Unlike bsptile itself, this isn't a from-scratch tiling
implementation -- yabai already does dynamic BSP tiling natively, so this
repo is the config/keybindings/glue layer that reproduces bsptile's specific
setup on top of it, plus a couple of small helper scripts for the one
feature yabai doesn't do out of the box (see below).

Scope note: this covers the tiling layer only (yabai + skhd + borders +
keybindings), same as `bsptile/` itself -- not a full machine bootstrap like
[ubuntstrap](https://github.com/z-con/ubuntstrap) covers for the Linux side.

## Feature mapping from bsptile

| bsptile (GNOME) | bsptile-mac (yabai/skhd) |
|---|---|
| Dynamic BSP auto-tiling | Native (`yabai -m config layout bsp`) |
| Inner/outer gaps (12px default) | Native (`window_gap`, `*_padding` in `yabairc`) |
| Border-drag resizing | Native (`mouse_action2 resize`) |
| Swap on drop | Native (`mouse_drop_action swap`) |
| Focus border (accent color outline) | JankyBorders (`bordersrc`) |
| Slightly transparent top panel | Not ported -- no yabai/macOS equivalent to a GNOME panel; menu bar isn't independently themeable this way |
| Deny fullscreen/maximize on open | `window_created` signal in `yabairc` |
| `Super+T` tile / `Super+Shift+T` untile | `cmd+alt-t` / `cmd+alt+shift-t` -> `bin/tile-focused.sh` / `bin/untile-focused.sh` |
| `Ctrl+Super+Arrow` resize divider | `ctrl+cmd+alt-arrows` -> `yabai -m window --resize` |
| Workspace/monitor migration | Native (yabai handles this) |
| Per-monitor virtual workspaces | Native per-display Spaces + `bin/space-focus.sh` / `bin/space-move.sh` for the `Super+1..9,0` mapping (see below) |
| Per-monitor slot indicator (dot row) | Not ported -- out of scope for the tiling layer; a menu-bar tool like [SketchyBar](https://github.com/FelixKratz/SketchyBar) could add this later |
| Terminal/app launch keybinds | `cmd+alt-return` / `cmd+alt+shift-return` / `ctrl+cmd+alt-return` in `skhdrc` |

**Modifier key**: bsptile used `Super` (Windows key) for everything, because
GNOME barely uses it. macOS leans on `Cmd` far more heavily for app and
system shortcuts, so this port uses **`cmd+alt`** as the base modifier
instead, to avoid fighting every app's own Cmd-based shortcuts.

**Per-monitor workspaces**: bsptile had to *simulate* per-monitor workspaces
in GJS (minimize/unminimize tricks) because Mutter has no native concept of
independent per-display workspaces. macOS actually has this natively --
each display gets its own row of Spaces in Mission Control when "Displays
have separate Spaces" is on (the default). `bin/space-focus.sh` and
`bin/space-move.sh` just resolve "slot N on the currently focused display"
to the right yabai space and create new slots on demand, matching bsptile's
dynamic-growing-slots behavior -- but riding real macOS Spaces instead of a
simulation.

## Requirements

- macOS with [Homebrew](https://brew.sh).
- A willingness to grant yabai and skhd Accessibility (and, on recent
  macOS, skhd Input Monitoring) permissions -- required by both tools,
  can't be scripted, see Install step 1 below.

## Install

```sh
git clone https://github.com/z-con/bsptile-mac.git
cd bsptile-mac
./install.sh
```

`install.sh` is safe to re-run. It will:

1. Install Homebrew if missing.
2. `brew install` yabai, skhd, borders, and jq (via their respective taps).
3. Symlink `yabairc` -> `~/.yabairc`, `skhdrc` -> `~/.skhdrc`, `bordersrc` ->
   `~/.config/borders/bordersrc`, backing up anything pre-existing that
   isn't already the symlink.
4. Restart the yabai/skhd/borders `brew services` so config takes effect.

It will then print a short list of manual, one-time macOS steps that
genuinely can't be scripted (Accessibility permissions, confirming
per-display Spaces is on, and turning off macOS's own drag-to-edge tiling
if it fights with yabai) -- read that output.

**Not automated on purpose**: yabai's *scripting addition* (which unlocks
borderless resizing across spaces and a few extra window rules) requires
partially disabling System Integrity Protection and a reboot into Recovery
Mode. That's a real security tradeoff, not something this script should
apply silently -- see the
[yabai wiki](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
if you want it; everything else in this repo works fine without it.

## Configuration

- **Gaps**: edit `window_gap` / `*_padding` in `yabairc`, then
  `brew services restart yabai` (or `yabai --restart-service`).
- **Focus border color/width**: edit `active_color`/`width` in `bordersrc`
  (hex is `0xAARRGGBB`), then `brew services restart borders`.
- **Keybindings**: edit `skhdrc`, then `brew services restart skhd` (or
  `skhd --reload`... skhd doesn't support that; restart the service).
- **App tiling rules**: add more `yabai -m rule --add app="..."` lines in
  `yabairc` for anything else that shouldn't be managed.

## Uninstall

```sh
brew services stop yabai skhd borders
rm ~/.yabairc ~/.skhdrc ~/.config/borders/bordersrc   # just the symlinks
brew uninstall yabai skhd borders jq   # optional
```

Accessibility permissions granted in System Settings aren't reverted
automatically -- remove yabai/skhd from that list yourself if you want to.

## Known limitations

- **`bin/space-focus.sh` and `bin/space-move.sh` are untested on real
  hardware** -- this repo was built on a Linux machine with no Mac to run
  yabai on. yabai's exact `space --create`/display-targeting flags have
  shifted across versions; if slot creation fails, check `man yabai` (or
  `yabai -m space --help`) against your installed version and fix the
  fallback in those two scripts. The core tiling/gaps/border config
  (`yabairc`, `bordersrc`) is far less likely to need changes since it's
  yabai's own documented, stable config surface.
- **No visual per-monitor slot indicator** -- bsptile's dot-row (`● ● ○ ○`)
  isn't ported. If you want one, a menu-bar tool like SketchyBar could read
  `yabai -m query --spaces` and render it, but that's a separate project
  from this tiling-layer repo.
- **Top-panel transparency isn't ported** -- there's no macOS/yabai
  equivalent to theming the GNOME panel this way.
- Directional focus movement (`cmd+alt-hjkl`) wasn't part of bsptile's own
  keymap -- it's added here because macOS's Cmd+Tab is app-based rather than
  window-based, so it doesn't substitute the way GNOME's Alt-Tab did for
  moving through a bsp tree.
