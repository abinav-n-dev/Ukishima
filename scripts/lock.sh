#!/bin/sh
# Ukishima session lock — dispatches on Flags.lockMethod.
#
#   "hyprlock"   → hyprlock, if it is actually installed
#   "quickshell" → lock-qs.sh (the Quickshell lock, which falls back to
#                  hyprlock by itself if Quickshell cannot lock)
#
# The flag is read from the ukishima flags.json (the same file the shell
# writes), so the pill's power menu and any keybind that runs lock.sh stay in
# sync.
#
# "hyprlock" is a hand-off, not a mode Ukishima configures. The repo ships no
# hyprlock.conf and generates none, so choosing it discards every visual
# setting on the LOCK surface — background, blur, avatar, indicators — in
# favour of the user's own hyprlock.conf. It is also an external dependency
# that may simply not be installed, so it is probed before use rather than
# exec'd on faith. That probe used to be missing here, which meant a machine
# without hyprlock ran `exec hyprlock`, got exit 127, and sat there unlocked.
#
# A missing hyprlock is never a reason to leave the session unlocked. The
# Quickshell lock needs nothing beyond Quickshell itself, so a request for
# hyprlock that cannot be honoured is downgraded to it and the downgrade is
# logged, not failed. Only when neither exists is this a real failure, and
# then it says so on stderr.
#
# The downgrade note goes in this log rather than lock-qs.log because
# lock-qs.sh truncates its own log on entry, which would eat it.
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ukishima"
LOG="$CACHE_DIR/lock.log"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

note() {
    mkdir -p "$CACHE_DIR" 2>/dev/null
    echo "$(date '+%F %T'): $*" >>"$LOG"
}

METHOD="hyprlock"
FLAGS_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ukishima/flags.json"
if [ -f "$FLAGS_FILE" ]; then
    val=$(sed -n 's/.*"lockMethod"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$FLAGS_FILE" | head -1)
    [ -n "$val" ] && METHOD="$val"
fi

have_hyprlock=0
command -v hyprlock >/dev/null 2>&1 && have_hyprlock=1
have_qs=0
[ -x "$SCRIPT_DIR/lock-qs.sh" ] && have_qs=1

if [ "$METHOD" = "hyprlock" ] && [ "$have_hyprlock" = 1 ]; then
    note "method=hyprlock -> hyprlock"
    exec hyprlock
fi

if [ "$have_qs" = 1 ]; then
    if [ "$METHOD" = "hyprlock" ]; then
        note "method=hyprlock but hyprlock is not installed -> downgrading to the Quickshell lock"
    else
        note "method=$METHOD -> lock-qs.sh"
    fi
    exec "$SCRIPT_DIR/lock-qs.sh"
fi

if [ "$have_hyprlock" = 1 ]; then
    note "lock-qs.sh is missing or not executable -> hyprlock"
    exec hyprlock
fi

note "ERROR no hyprlock and no $SCRIPT_DIR/lock-qs.sh — nothing to lock with"
echo "lock.sh: no hyprlock installed and no $SCRIPT_DIR/lock-qs.sh — cannot lock" >&2
exit 1
