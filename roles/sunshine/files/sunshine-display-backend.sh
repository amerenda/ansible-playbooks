#!/bin/bash
# Virtual-display backend for KDE Plasma 6 / Wayland (KWin), sourced by
# sunshine-connect.sh / sunshine-disconnect.sh.
#
# KWin has no command to spawn a headless output on demand, so krfb-virtualmonitor
# creates one at the *compositor* level (userspace only, no kernel module) —
# Sunshine must capture it with `capture = kwin` (the kms backend can't see
# compositor-level outputs). Adapted from:
# https://github.com/jhonsnake/sunshine-kde-virtual-display
#
# Public interface (consumed by sunshine-connect.sh / sunshine-disconnect.sh):
#   create_virtual_display <WxH> <name-hint>  -> creates the output
#   get_virtual_display_name                  -> echoes the name KWin assigned
#   destroy_virtual_display                   -> tears it down
LOG="${LOG:-$HOME/.local/share/sunshine-headless.log}"
VDISPLAY_PIDFILE="$HOME/.local/share/sunshine-vdisplay.pid"
VDISPLAY_NAMEFILE="$HOME/.local/share/sunshine-vdisplay.name"

log() { echo "$(date -Iseconds) $*" >> "$LOG"; }

_kscreen_output_names() {
    kscreen-doctor -j 2>/dev/null \
        | python3 -c "import sys,json; [print(o['name']) for o in json.load(sys.stdin).get('outputs',[])]"
}

create_virtual_display() {
    local res="$1" name_hint="$2"
    # Snapshot existing outputs so we can identify the *new* one afterwards —
    # the assigned name isn't guaranteed to equal name_hint, so diffing the
    # output list is the robust way to discover it.
    local before after new
    before="$(_kscreen_output_names | sort)"

    # --desktopfile NONE keeps it headless (no tray entry); the VNC port is
    # incidental (localhost) — we only want the virtual output it spawns.
    # setsid + stdin from /dev/null fully detaches it: krfb-virtualmonitor is a
    # long-lived daemon for the whole session, and without this an inherited
    # stdin keeps the invoking process (Sunshine's prep-cmd exec, or an
    # interactive SSH test) waiting on it instead of returning immediately.
    setsid krfb-virtualmonitor --resolution "$res" --name "$name_hint" \
        --password "" --desktopfile NONE --scale 1 --port 5921 \
        < /dev/null >> "$LOG" 2>&1 &
    disown
    echo $! > "$VDISPLAY_PIDFILE"

    # Wait for KWin to register the new output (poll up to ~4s).
    for _ in $(seq 1 20); do
        sleep 0.2
        after="$(_kscreen_output_names | sort)"
        new="$(comm -13 <(echo "$before") <(echo "$after") | head -n1)"
        [ -n "$new" ] && break
    done

    if [ -z "$new" ]; then
        log "ERROR: krfb-virtualmonitor did not produce a new output"
        return 1
    fi
    echo "$new" > "$VDISPLAY_NAMEFILE"
    log "created virtual output: $new (${res})"
}

get_virtual_display_name() {
    [ -f "$VDISPLAY_NAMEFILE" ] && cat "$VDISPLAY_NAMEFILE"
}

destroy_virtual_display() {
    [ -f "$VDISPLAY_PIDFILE" ] && kill "$(cat "$VDISPLAY_PIDFILE")" 2>/dev/null
    rm -f "$VDISPLAY_PIDFILE" "$VDISPLAY_NAMEFILE"
}
