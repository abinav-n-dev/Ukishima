#!/bin/sh
# Ukishima session lock — dispatches on Flags.lockMethod.
#
#   "hyprlock"   → exec hyprlock directly (the default)
#   "quickshell" → run lock-qs.sh (quickshell lockscreen, hyprlock fallback)
#
# The flag is read from the ukishima flags.json (the same file the shell
# writes), so the pill's power menu and any keybind that runs lock.sh stay
# in sync. An unreadable or missing flag falls back to hyprlock.
FLAGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/ukishima/flags.json"
METHOD="hyprlock"
if [ -f "$FLAGS_FILE" ]; then
    val=$(sed -n 's/.*"lockMethod"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FLAGS_FILE" | head -1)
    [ -n "$val" ] && METHOD="$val"
fi
if [ "$METHOD" = "quickshell" ]; then
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    exec "$SCRIPT_DIR/lock-qs.sh"
fi
exec hyprlock
