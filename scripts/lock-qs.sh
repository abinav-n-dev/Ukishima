#!/bin/sh
# Ukishima session lock — Quickshell lockscreen, falling back to hyprlock.
#
# Opt-in: scripts/lock.sh still execs hyprlock. Point your idle locker at
# this one instead:
#     lock_cmd = ~/.local/share/quickshell/ukishima/scripts/lock-qs.sh
#
# Every attempt is logged so a dead keybind can be told apart from a
# lockscreen that failed to start. The log lives in the cache dir like
# every other Ukishima script (see scripts/check-deps.sh).
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ukishima"
LOG="$CACHE_DIR/lock-qs.log"
mkdir -p "$CACHE_DIR"
: > "$LOG"
echo "$(date '+%F %T'): lock requested (args: $*)" >>"$LOG"

QS_BIN="$(command -v quickshell 2>/dev/null || command -v qs 2>/dev/null)"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LOCK_QML="$SCRIPT_DIR/../lockscreen/shell.qml"

# Pre-capture the desktop, the way hyprlock's `path = screenshot` does.
# grim has to finish BEFORE the lock covers the screen: a ScreencopyView
# inside ext-session-lock is racy on Hyprland/NVIDIA and usually comes
# back empty or torn. Blocking on purpose.
if command -v grim >/dev/null 2>&1; then
    rm -f "$CACHE_DIR/lock-shot.png"
    if ! grim "$CACHE_DIR/lock-shot.png" >>"$LOG" 2>&1; then
        echo "$(date '+%F %T'): grim failed, continuing without pre-capture" >>"$LOG"
    fi
fi

if [ -n "$QS_BIN" ] && [ -f "$LOCK_QML" ]; then
    # Quickshell parses and validates the QML before rendering, so it
    # exits non-zero immediately if an import (e.g. a missing compiled
    # module) cannot be resolved. If we exec'd it here, the hyprlock
    # fallback below would be unreachable and the session would stay
    # unlocked while appearing to lock. Run in the foreground instead.
    echo "$(date '+%F %T'): starting $QS_BIN -p $LOCK_QML" >>"$LOG"
    "$QS_BIN" -p "$LOCK_QML" >>"$LOG" 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
        echo "$(date '+%F %T'): quickshell exited 0 — lock released cleanly" >>"$LOG"
        exit 0
    fi
    echo "$(date '+%F %T'): quickshell exited $rc — locking failed, falling back" >>"$LOG"
fi

# Never exit without locking: a missing quickshell or a partial checkout
# must still leave the session protected.
echo "$(date '+%F %T'): quickshell or lockscreen/shell.qml missing — falling back" >>"$LOG"
if command -v hyprlock >/dev/null 2>&1; then
    echo "$(date '+%F %T'): exec hyprlock" >>"$LOG"
    exec hyprlock
fi

echo "$(date '+%F %T'): ERROR no quickshell and no hyprlock — nothing to lock with" >>"$LOG"
exit 1
