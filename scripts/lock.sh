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
#
# The hyprlock path is also a singleton: a repeat request while a lock is up is
# a logged no-op, and instances started outside this script are reaped. See
# run_hyprlock below for why, and for the guard's fail-open rule.
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

# Only one process can hold the Wayland session lock, so a second hyprlock can
# never improve on a first: it either fails to take the lock, or stacks an
# identical surface behind the live one where no dismiss can reach it. Either
# way it never exits, and each instance parks ~167 MiB of renderer for the rest
# of the session -- 34 of them were once resident here, 5.5 GiB total.
#
# `exec` preserves the pid, so writing $$ before handing over names the exact
# process this script started. A live recorded pid means the session is already
# locked and the request is a no-op; anything else is stale bookkeeping.
#
# Every failure path below still execs. Leaving the session unlocked to save
# 167 MiB would be the wrong trade, so the guard fails open at each step.
PIDFILE="$CACHE_DIR/hyprlock.pid"

hyprlock_is_live() {
    [ -f "$PIDFILE" ] || return 1
    pid=$(cat "$PIDFILE" 2>/dev/null)
    case "$pid" in '' | *[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    # A recycled pid must not read as "locked": confirm it is really hyprlock.
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "hyprlock" ] || return 1
    return 0
}

# Reap instances this script did not start. Only reached on the path where a
# fresh lock is being taken, so a stray that happens to hold the lock is
# replaced within the same request instead of being left to linger.
reap_stray_hyprlocks() {
    command -v pkill >/dev/null 2>&1 || return 0
    strays=$(pgrep -x hyprlock 2>/dev/null | wc -l)
    if [ "$strays" -gt 0 ]; then
        pkill -x hyprlock 2>/dev/null
        sleep 0.3
        note "reaped $strays stray hyprlock instance(s) from an earlier lock request"
    fi
    return 0
}

run_hyprlock() {
    if hyprlock_is_live; then
        note "hyprlock already running (pid $(cat "$PIDFILE" 2>/dev/null)) -> session is already locked, not spawning another"
        exit 0
    fi
    rm -f "$PIDFILE"
    reap_stray_hyprlocks
    mkdir -p "$CACHE_DIR" 2>/dev/null
    echo $$ >"$PIDFILE"
    exec hyprlock
}

if [ "$METHOD" = "hyprlock" ] && [ "$have_hyprlock" = 1 ]; then
    note "method=hyprlock -> hyprlock"
    run_hyprlock
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
    run_hyprlock
fi

note "ERROR no hyprlock and no $SCRIPT_DIR/lock-qs.sh — nothing to lock with"
echo "lock.sh: no hyprlock installed and no $SCRIPT_DIR/lock-qs.sh — cannot lock" >&2
exit 1
