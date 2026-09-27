#!/bin/sh
# Apply the shell's idle timeouts to hypridle's config and restart the daemon.
#
#   lock-idle.sh <lockMin> <screenOffMin> <suspendMin>
#   lock-idle.sh --read
#
# Minutes; 0 disables that listener. The three values come from the LOCK
# settings surface (Flags.idleLockMin / idleScreenOffMin / idleSuspendMin).
#
# --read prints "<lock> <screen> <suspend>" in minutes and changes nothing, so
# the surface can show what hypridle is actually doing rather than whatever the
# flags happen to hold. Blocks it cannot find fall back to the Flags defaults.
#
# Only the `timeout = ` line of the three matching listener blocks is rewritten,
# in place and matched by content rather than by line number: the lock block is
# the one whose `on-timeout` runs a lock script, the screen block the one that
# turns DPMS off, the suspend block the one that calls systemctl suspend. Every
# comment, blank line and ordering in the file is preserved byte for byte, and a
# backup is taken before the first write.
#
# Matching is done per block, not per line, because a listener puts `timeout`
# before `on-timeout` — so the key is only known once the whole block has been
# read.
#
# hypridle has no reload, so the daemon is restarted to pick the file up. It is
# re-execed detached, and the exit status says whether the change was applied.

LOG=/tmp/ukishima-idle.log
# UKISHIMA_HYPRIDLE_CONF overrides the target. Defaults to the user's own
# hypridle.conf, which is what a hand-written setup like ours uses. A generated
# file inside the project folder (the hyprsunset.conf precedent) can be pointed
# at instead by exporting this, in which case nothing outside the project is
# touched.
CONF="${UKISHIMA_HYPRIDLE_CONF:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hypridle.conf}"

log() { echo "$(date '+%F %T'): $*" >>"$LOG"; }

LOCK_MIN=$1
SCREEN_MIN=$2
SUSPEND_MIN=$3

# Read mode: report the live timeouts, never touch anything. The awk below is the
# same block matcher as the write path, only it keeps the value instead of
# replacing it, so the two can never disagree about which block is which.
if [ "$LOCK_MIN" = "--read" ]; then
    [ -f "$CONF" ] || { echo "5 6 0"; exit 0; }
    vals=$(awk '
        function flush(   i, k, v) {
            if (n == 0) return
            k = ""
            for (i = 1; i <= n; i++) {
                if (buf[i] ~ /on-timeout/) {
                    if (klock == "" && buf[i] ~ /lock/) k = "lock"
                    else if (kscreen == "" && buf[i] ~ /dpms/ && buf[i] ~ /off/) k = "screen"
                    else if (ksuspend == "" && buf[i] ~ /suspend/) k = "suspend"
                }
            }
            for (i = 1; i <= n; i++) {
                if (buf[i] ~ /^[[:space:]]*timeout[[:space:]]*=/) {
                    v = buf[i]
                    sub(/^[^0-9]*/, "", v)
                    sub(/[^0-9].*$/, "", v)
                    if (k == "lock" && klock == "") klock = v
                    else if (k == "screen" && kscreen == "") kscreen = v
                    else if (k == "suspend" && ksuspend == "") ksuspend = v
                }
            }
            n = 0
        }
        BEGIN { n = 0; inblock = 0 }
        {
            if (!inblock && $0 ~ /^[[:space:]]*listener[[:space:]]*\{/) { inblock = 1; n = 1; buf[1] = $0; next }
            if (inblock) {
                if ($0 ~ /^[[:space:]]*\}/) { buf[++n] = $0; flush(); inblock = 0; next }
                buf[++n] = $0
                next
            }
        }
        END {
            if (inblock) flush()
            # hypridle reads a 0 timeout as "never", so 0 stays 0; a missing
            # block falls back to the Flags default.
            printf "%d %d %d\n", (klock == "" ? 300 : klock) / 60, (kscreen == "" ? 360 : kscreen) / 60, (ksuspend == "" ? 0 : ksuspend) / 60
        }
    ' "$CONF" 2>/dev/null) || vals="5 6 0"
    echo "${vals:-5 6 0}"
    exit 0
fi

for v in "$LOCK_MIN" "$SCREEN_MIN" "$SUSPEND_MIN"; do
    case "$v" in
        ''|*[!0-9]*)
            log "ERROR: non-numeric argument '$v' — refusing to touch $CONF"
            exit 2
            ;;
    esac
done

[ -f "$CONF" ] || { log "ERROR: $CONF not found — nothing changed"; exit 1; }

log "requested lock=${LOCK_MIN}m screen=${SCREEN_MIN}m suspend=${SUSPEND_MIN}m"

TMP=$(mktemp "${CONF}.ukishima.XXXXXX") || { log "ERROR: mktemp failed"; exit 1; }
trap 'rm -f "$TMP"' EXIT INT TERM

awk -v lock_secs=$((LOCK_MIN * 60)) \
    -v screen_secs=$((SCREEN_MIN * 60)) \
    -v suspend_secs=$((SUSPEND_MIN * 60)) '
    function secs(k) { return k == "lock" ? lock_secs : (k == "screen" ? screen_secs : suspend_secs) }
    function isdone(k) { return k == "lock" ? done_lock : (k == "screen" ? done_screen : done_suspend) }
    function mark(k) {
        if (k == "lock") done_lock = 1
        else if (k == "screen") done_screen = 1
        else done_suspend = 1
    }
    # Emit the buffered listener block, rewriting its timeout if this block is
    # one of ours and we have not already handled that key.
    function flush(   i, k, pre) {
        if (n == 0) return
        k = ""
        for (i = 1; i <= n; i++) {
            if (buf[i] ~ /on-timeout/) {
                if (!isdone("lock") && buf[i] ~ /lock/) { k = "lock"; break }
                if (!isdone("screen") && buf[i] ~ /dpms/ && buf[i] ~ /off/) { k = "screen"; break }
                if (!isdone("suspend") && buf[i] ~ /suspend/) { k = "suspend"; break }
            }
        }
        for (i = 1; i <= n; i++) {
            if (k != "" && !replaced && buf[i] ~ /^[[:space:]]*timeout[[:space:]]*=/) {
                match(buf[i], /^[[:space:]]*/)
                printf "%stimeout = %d\n", substr(buf[i], 1, RLENGTH), secs(k)
                replaced = 1
            } else print buf[i]
        }
        if (k != "" && replaced) mark(k)
        n = 0
        replaced = 0
    }
    BEGIN { n = 0; inblock = 0 }
    {
        line = $0
        if (!inblock && line ~ /^[[:space:]]*listener[[:space:]]*\{/) {
            inblock = 1
            n = 1
            buf[1] = line
            next
        }
        if (inblock) {
            if (line ~ /^[[:space:]]*\}/) { buf[++n] = line; flush(); inblock = 0; next }
            buf[++n] = line
            next
        }
        print line
    }
    END { if (inblock) flush() }
' "$CONF" >"$TMP" || { log "ERROR: awk failed — $CONF untouched"; exit 1; }

# Refuse to install a result that lost structure: hypridle silently ignoring a
# broken file is worse than not applying the change at all.
before_listeners=$(grep -c '^[[:space:]]*listener' "$CONF" || true)
after_listeners=$(grep -c '^[[:space:]]*listener' "$TMP" || true)
if [ "$before_listeners" != "$after_listeners" ]; then
    log "ERROR: listener count changed ($before_listeners -> $after_listeners) — $CONF untouched"
    exit 1
fi

if cmp -s "$CONF" "$TMP"; then
    log "no change needed (already lock=${LOCK_MIN}m screen=${SCREEN_MIN}m suspend=${SUSPEND_MIN}m)"
    exit 0
fi

if [ ! -f "$CONF.ukishima.bak" ]; then
    cp -p "$CONF" "$CONF.ukishima.bak" || { log "ERROR: backup failed — $CONF untouched"; exit 1; }
    log "first write: backup at $CONF.ukishima.bak"
fi

cat "$TMP" >"$CONF" || { log "ERROR: write failed — $CONF may be truncated, restore from $CONF.ukishima.bak"; exit 1; }
log "wrote $CONF (lock=${LOCK_MIN}m screen=${SCREEN_MIN}m suspend=${SUSPEND_MIN}m)"

# hypridle reads its config once at startup, so a restart is the only way to
# apply. execs.lua starts it as `pidof hypridle || hypridle`, so nothing brings
# it back automatically — re-exec it here, detached, or idle locking is silently
# gone for the rest of the session.
if command -v pkill >/dev/null 2>&1; then
    pkill -x hypridle 2>/dev/null
    sleep 0.3
fi
if command -v hypridle >/dev/null 2>&1; then
    setsid hypridle >/dev/null 2>&1 &
    sleep 0.5
    if pgrep -x hypridle >/dev/null 2>&1; then
        log "hypridle restarted and running"
        exit 0
    fi
    log "ERROR: hypridle did not come back up — restore $CONF.ukishima.bak and run: hypridle"
    exit 1
fi

log "ERROR: hypridle binary not found — config written but not applied"
exit 1
