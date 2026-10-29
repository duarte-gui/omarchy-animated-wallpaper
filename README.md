# Animated Wallpaper for Omarchy 4

Play a folder of videos as your desktop wallpaper with [mpvpaper](https://github.com/GhostNaN/mpvpaper), controlled from a button in the Omarchy bar.

This is a fork of [jacobobb/omarchy-animated-wallpaper](https://github.com/jacobobb/omarchy-animated-wallpaper), ported to **Omarchy 4**. Omarchy 4 replaced Waybar and swaybg with the Quickshell-based Omarchy shell, so the original Waybar module and installer no longer work there. Here the button is a native Omarchy shell bar widget, and the wallpaper works from a folder of videos instead of a single file.

## Features

- Loops one video from a folder until you switch with a middle click (or, optionally, moves on whenever a video ends)
- Remembers which video was playing and comes back to it
- Choose the folder from the bar (right click) or in the widget settings
- Remembers whether it was on, so the video comes back after you log in
- Keeps playing through shell restarts and Omarchy updates
- Pauses while windows cover the whole desktop, so it costs no GPU when hidden
- Decodes on the GPU when it can (`hwdec=auto`), no audio
- Desktop double-clicks still reach Omarchy (background picker and theme switcher)
- Plays on every monitor

## Requirements

- Omarchy 4 (tested on 4.0.6, Hyprland 0.56)
- [mpvpaper](https://aur.archlinux.org/packages/mpvpaper): `yay -S mpvpaper`
- `zenity`, `jq` and `rsync`, which Omarchy already ships

## Install

With the Omarchy plugin manager:

```bash
yay -S mpvpaper
omarchy plugin add https://github.com/duarte-gui/omarchy-animated-wallpaper.git --enable
```

Or from a clone, which also puts the button on the bar:

```bash
yay -S mpvpaper
git clone https://github.com/duarte-gui/omarchy-animated-wallpaper.git
cd omarchy-animated-wallpaper
./install.sh
```

Then right-click the video icon in the bar and choose a folder of videos.

## Usage

### Bar button

| Action | Result |
|--------|--------|
| Left click | Turn the wallpaper on or off |
| Right click | Choose the video folder (and turn it on) |
| Middle click | Switch to the next video in the folder |
| Hover | Folder, number of videos, or the last error |

The icon is dimmed while the wallpaper is off and turns red if it could not start, for example when the folder has no videos. In that case the video that was already playing keeps playing.

### Settings

The settings live inline in `~/.config/omarchy/shell.json`, on the `io.github.duarte-gui.animated-wallpaper` entry. You can edit them in the shell's settings or with `omarchy bar set`:

| Key | Default | What it does |
|-----|---------|--------------|
| `videoDir` | `~/Videos/Wallpapers` | Folder whose videos play as the wallpaper. Subfolders are not included. |
| `enabled` | `false` | Whether the wallpaper is playing. The left click flips it. |
| `order` | `sequential` | Order the middle click walks through: `sequential` (name order) or `shuffle` |
| `advance` | `manual` | `manual` loops the current video until the middle click; `end` moves on whenever a video finishes |
| `pauseWhenHidden` | `true` | Pause while windows cover the whole desktop |
| `mpvOptions` | `""` | Extra mpv options, e.g. `panscan=1.0` to fill the screen without black bars |
| `currentVideo` | `""` | The video it starts on. The middle click keeps this up to date; empty means the first video. |

```bash
omarchy bar set io.github.duarte-gui.animated-wallpaper videoDir ~/Videos/Wallpapers
omarchy bar set io.github.duarte-gui.animated-wallpaper order shuffle
```

Supported formats are the ones mpv treats as video (mp4, webm, mkv, mov, avi, m4v, …) plus gif.

### Keybindings and scripts

```bash
omarchy-shell animated-wallpaper toggle   # on/off
omarchy-shell animated-wallpaper on
omarchy-shell animated-wallpaper off
omarchy-shell animated-wallpaper pick     # folder picker
omarchy-shell animated-wallpaper next     # switch to the next video
omarchy-shell animated-wallpaper status
```

For example, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + W", "Toggle animated wallpaper", "omarchy-shell animated-wallpaper toggle")
```

## How it works

- `BarWidget.qml` is the bar button. It owns the settings and calls `bin/wallpaper-video`. The middle click goes through mpv's IPC socket, so switching videos does not restart the player.
- `bin/wallpaper-video` builds a playlist from the folder (starting on the remembered video), loops the current file with mpv's `loop-file`, and starts mpvpaper in its own session, so a shell restart or plugin reload does not stop it. The bar only restarts it when a setting actually changes.
- mpvpaper draws on the Wayland **bottom** layer. That is above the static wallpaper that `omarchy.background` draws on the background layer, and below every window. Using the bottom layer keeps the video on top even when the shell recreates its background. mpvpaper's surface takes no input, so clicks on the desktop still go to Omarchy.
- Turning it off removes that layer, and your normal Omarchy wallpaper and theme commands (`omarchy theme set`, `omarchy theme bg next`) keep working as before.

## Uninstall

If you installed it with `install.sh`, this stops the wallpaper and removes the widget:

```bash
./install.sh --uninstall
```

If you installed it with `omarchy plugin add`, turn the wallpaper off first (left click), because removing the plugin does not stop a video that is playing:

```bash
omarchy-shell animated-wallpaper off
omarchy plugin remove io.github.duarte-gui.animated-wallpaper
```

If you already removed it with the video still on, `pkill -x mpvpaper` stops it.

## License

MIT. Original work by Jacobo Blancas; Omarchy 4 port by duarte-gui.
