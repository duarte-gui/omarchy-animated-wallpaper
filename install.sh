#!/bin/bash
#
# Install the Animated Wallpaper bar widget into the running Omarchy 4 shell.
#
#   ./install.sh              sync, validate, rescan, and put it on the bar on first run
#   ./install.sh --enable     force the bar placement even if already installed
#   ./install.sh --uninstall  stop the wallpaper, take it off the bar, remove the installed copy
#   ./install.sh --force      overwrite an install that omarchy plugin add made
#
# The shell only watches real files under ~/.config/omarchy/plugins, and
# omarchy-plugin-validate rejects symlinks inside a plugin folder, so this
# copies rather than links.

set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SECTION="${ANIMATED_WALLPAPER_SECTION:-right}"

MODE="install"
FORCE="no"
FORCE_ENABLE="no"

while (($# > 0)); do
  case "$1" in
  --uninstall) MODE="uninstall" ;;
  --enable) FORCE_ENABLE="yes" ;;
  --force) FORCE="yes" ;;
  -h | --help)
    sed -n '3,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    echo "install.sh: unknown option '$1'" >&2
    exit 1
    ;;
  esac
  shift
done

die() {
  echo "install.sh: $*" >&2
  exit 1
}

for tool in jq rsync omarchy-plugin-validate omarchy-shell; do
  command -v "$tool" >/dev/null 2>&1 || die "missing required command: $tool"
done

[[ -f $SRC/manifest.json ]] || die "no manifest.json next to this script"
ID="$(jq -r '.id // empty' "$SRC/manifest.json")"
[[ -n $ID ]] || die "manifest.json has no id"

DEST="$HOME/.config/omarchy/plugins/$ID"
SHELL_JSON="$HOME/.config/omarchy/shell.json"

if [[ $MODE == uninstall ]]; then
  "$SRC/bin/wallpaper-video" stop || true
  omarchy plugin disable "$ID" >/dev/null 2>&1 || true
  [[ $SRC != "$DEST" ]] && rm -rf "$DEST"
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  echo "removed $ID"
  exit 0
fi

[[ $SRC != "$DEST" ]] || die "already running from the plugins directory; nothing to sync"

# Checked before installing anything, so a missing player is reported up front
# instead of as an error the first time the button is clicked.
command -v mpvpaper >/dev/null 2>&1 || die "mpvpaper is not installed. Install it with: yay -S mpvpaper"
command -v zenity >/dev/null 2>&1 || die "zenity is not installed (used by the folder picker): sudo pacman -S zenity"

# An install made by `omarchy plugin add` is a git checkout; rsync --delete
# would take its working tree with it.
if [[ -d $DEST/.git && $FORCE != yes ]]; then
  die "$DEST is a git checkout from 'omarchy plugin add'.
  Update it with 'omarchy plugin update $ID', or pass --force to overwrite it."
fi

mkdir -p "$DEST"
# --delete is what makes a renamed or removed file actually disappear from the
# installed copy. rsync writes a temp file then renames it, which raises the
# inotify move event the shell's plugin watcher listens for.
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.github/' \
  --exclude '.*.swp' \
  --exclude '*~' \
  "$SRC/" "$DEST/"

omarchy plugin validate "$DEST"

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# Enabling before the shell has finished discovering the plugin fails with
# "plugin is not known", so wait for it the same way omarchy-plugin-add does.
known="no"
for _ in $(seq 1 40); do
  if omarchy-plugin-list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id)' >/dev/null 2>&1; then
    known="yes"
    break
  fi
  sleep 0.05
done
[[ $known == yes ]] || die "the shell did not pick up $ID — check its log with: journalctl --user -e | grep -i quickshell"

# Re-enabling an already-placed widget appends a duplicate layout entry.
placed="no"
if [[ -f $SHELL_JSON ]] && jq -e --arg id "$ID" '[.. | objects | select(.id? == $id)] | length > 0' "$SHELL_JSON" >/dev/null 2>&1; then
  placed="yes"
fi

if [[ $placed == no || $FORCE_ENABLE == yes ]]; then
  omarchy plugin enable "$ID" --section "$SECTION"
  echo "enabled $ID in the $SECTION section"
else
  echo "$ID is already on the bar; left its position alone"
fi

cat <<EOF

Animated Wallpaper installed.

  Right-click the video icon in the bar to choose a folder of videos.
  Settings live inline in $SHELL_JSON, on the "$ID" entry.
  Drive it with: omarchy-shell animated-wallpaper toggle | on | off | pick | next | status
EOF
