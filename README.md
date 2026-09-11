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
| Workspace/monitor migration | Native (yabai handles this); on disconnect, `bin/handle-display-removed.sh` switches to where macOS actually put the windows (see below) |
| Per-monitor virtual workspaces | Native per-display Spaces + `bin/space-focus.sh` / `bin/space-move.sh` for the `Super+1..9,0` mapping (see below) |
| Direct workspace jump (no creation) | Not from bsptile -- `cmd-1..9,0` -> `bin/space-goto.sh` (see below) |
| Dynamic workspaces (destroy empty ones on leave, keep one spare) | `bin/purge-empty-space.sh` on `space_changed` + `bin/ensure-spare-space.sh` on `window_created` + `bin/consolidate-spare-spaces.sh` on `window_destroyed` (see below) |
| Per-monitor slot indicator (dot row) | Not ported -- out of scope for the tiling layer; a menu-bar tool like [SketchyBar](https://github.com/FelixKratz/SketchyBar) could add this later |
| Terminal/app launch keybinds | `cmd-return` / `cmd+alt-return` (new Ghostty window, via `bin/new-ghostty-window.sh`) / `cmd+alt+shift-return` / `ctrl+cmd+alt-return` in `skhdrc` |

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
simulation. Slot creation goes through Mission Control's own "+" button via
Accessibility rather than `yabai -m space --create`, which needs SIP
partially disabled -- see `bin/create-space.sh`.

**Direct workspace jump**: `cmd-1..9,0` (bare Cmd, not `cmd+alt` like the
slot bindings above) jumps straight to slot N on the currently focused
display via `bin/space-goto.sh` -- unlike `space-focus.sh`, it never
creates new slots; if N is beyond however many currently exist, it lands
on the last one (the spare) instead. Note this globally overrides whatever
Cmd+1..9 already does inside individual apps (browser tab switching,
Finder view modes, and similar) -- exactly the kind of collision `cmd+alt`
was chosen everywhere else in this repo to avoid.

**Dynamic workspaces**: mirroring bsptile's own behavior, two complementary
scripts keep exactly one empty "spare" space at the end of each display's
row, matching bsptile's own dynamic-workspaces model. `bin/purge-empty-
space.sh` (on `space_changed`) destroys a space you navigate away from if
it's empty, except the one empty space immediately after the last occupied
space on its display -- that one's kept as the always-available spare.
`bin/ensure-spare-space.sh` (on `window_created`) is the second: when a
new window lands on what's currently the last space on its display -- the
spare just got used -- it creates a fresh one after it, including when you
open the window without ever switching spaces (e.g. Cmd+Return while
already sitting on the spare). A third, `bin/consolidate-spare-spaces.sh`
(on `window_destroyed`), covers the gap neither of the first two can:
closing the last window on a space you're still sitting on doesn't trigger
`space_changed` (you never left) or create a new window, so the spare that
came before it can be left behind with nothing to clean it up -- this
sweeps every display for any empty, unfocused space beyond the properly
reserved one and removes it. All three need a workaround for the same SIP
requirement as slot creation: `yabai -m space --create`/`--destroy` won't
work without it, so `bin/create-space.sh` and `bin/remove-desktop.sh` (the
shared mechanism the other two call into) drive Mission Control's own
per-Desktop "+" and remove (`AXRemoveDesktop`) actions via Accessibility
instead, retrying if a first attempt doesn't visibly take effect -- this
automation has been flaky often enough to need it. The visible cost is
that Mission Control briefly flashes open and closed on screen each time a
space gets purged or created.

**External monitor disconnect**: when a display disconnects, macOS itself
already merges its windows onto space 1 on the remaining display -- there's
no way to stop or redirect that. `bin/handle-display-removed.sh` (on
`display_removed`) just switches monitor 1 to that space, so you're looking
at where the windows actually landed instead of wherever you happened to be
working. Deliberately just that: two earlier, more ambitious versions tried
to actively redistribute the windows via synthetic drag-and-hold automation
(the same technique used for the tricks above) -- first onto freshly
created spaces preserving their original per-monitor groupings, then onto
monitor 1's single spare space. Both worked in isolated testing; the first
was unusably slow and visually chaotic on real hardware (worse, a real
physical unplug fired `display_removed` more than once in quick succession,
so multiple copies ran at once), and the second, while much lighter, still
wasn't the experience wanted. This version has no automation left to go
wrong.

On reconnect, macOS moves those windows back to the external display on its
own -- but can leave space 1 empty with nothing to notice: purge-empty-
space.sh only fires when you navigate *away* from a space, and these
windows didn't close (`window_destroyed`) either, they just changed
displays, so neither existing cleanup path reacts on its own. `display_
added` reuses `consolidate-spare-spaces.sh` (the same sweep already used
for the close-your-last-window-without-navigating-away gap) after a brief
settle delay, rather than a dedicated script.

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
4. Compile `bin/ghostty-new-window.applescript` into `bin/ghostty-new-window.app`
   (used by the Cmd+Return keybind -- see Configuration below).
5. Start/restart yabai and skhd via `--start-service` (not `brew services` --
   neither formula implements brew's service hooks) and restart the borders
   `brew services` entry, so config takes effect.

It will then print a short list of manual, one-time macOS steps that
genuinely can't be scripted (Accessibility permissions, confirming
per-display Spaces is on, turning off macOS's own drag-to-edge tiling if it
fights with yabai, and one Automation-permission grant for the new-window
helper app) -- read that output.

**Not automated on purpose**: yabai's *scripting addition* (which unlocks
borderless resizing across spaces and a few extra window rules) requires
partially disabling System Integrity Protection and a reboot into Recovery
Mode. That's a real security tradeoff, not something this script should
apply silently -- see the
[yabai wiki](https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection)
if you want it; everything else in this repo works fine without it.

## Configuration

- **Gaps**: edit `window_gap` / `*_padding` in `yabairc`, then
  `yabai --restart-service` (yabai manages its own launchd service, not
  `brew services`).
- **Focus border color/width**: edit `active_color`/`width` in `bordersrc`
  (hex is `0xAARRGGBB`), then `brew services restart borders`.
- **Keybindings**: edit `skhdrc`, then `skhd --stop-service && skhd --start-service`
  (skhd also manages its own service, and doesn't support a live reload).
- **App tiling rules**: add more `yabai -m rule --add app="..."` lines in
  `yabairc` for anything else that shouldn't be managed.
- **New-window helper app**: `bin/ghostty-new-window.app` is compiled from
  `bin/ghostty-new-window.applescript` by `install.sh`; edit the `.applescript`
  source and re-run `install.sh` (or `osacompile -o bin/ghostty-new-window.app
  bin/ghostty-new-window.applescript`) to change it.

## Uninstall

```sh
yabai --stop-service
skhd --stop-service
brew services stop borders
rm ~/.yabairc ~/.skhdrc ~/.config/borders/bordersrc   # just the symlinks
brew uninstall yabai skhd borders jq   # optional
```

Accessibility permissions granted in System Settings aren't reverted
automatically -- remove yabai/skhd from that list yourself if you want to.

## Known limitations

- **Slot creation and empty-space purging go through Mission Control's own
  UI, not yabai directly** -- `yabai -m space --create`/`--destroy` and
  `window --space` all need System Integrity Protection partially disabled
  (yabai's scripting-addition), which is a real security tradeoff this repo
  doesn't apply for you. `bin/create-space.sh` and `bin/purge-empty-space.sh`
  instead drive Mission Control's own "+" button and per-Desktop
  `AXRemoveDesktop` action via Accessibility, which needs no such tradeoff --
  see those two scripts for how. The cost: each briefly flashes Mission
  Control open and closed on screen, and `bin/space-move.sh`'s window-move
  step (`yabai -m window --space`) still needs SIP partially disabled, so
  moving a window to another slot doesn't work without that.
- **Both untested with multiple displays** -- Mission Control shows a
  separate Spaces Bar per display when "Displays have separate Spaces" is
  on; `create-space.sh`/`purge-empty-space.sh` target whichever one they
  find first under the Dock process's UI tree, which is unambiguous on a
  single display but may not hit the intended one on a multi-monitor setup.
- **A slot created only to reach a higher one can be left behind empty** --
  jumping straight to slot 5 with only 3 slots existing creates 4 and 5, but
  purging only evaluates a space when you actually navigate away from it, so
  slot 4 (never visited) can sit there until something eventually does.
- **External monitor disconnect assumes macOS always merges onto space 1**
  -- that's what was observed on the one real disconnect this was tested
  against, not something documented or guaranteed by macOS. If a future
  macOS version (or a different setup) merges onto a different space
  instead, `handle-display-removed.sh` would need updating to match.
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
