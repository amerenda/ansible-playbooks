#!/bin/bash
# Sunshine global_prep_cmd "undo" — the client disconnected. Restore local use.
# ORDER MATTERS: re-enable the physical output(s) FIRST so a failure in any
# later step never leaves the machine blind.
# Adapted from https://github.com/jhonsnake/sunshine-kde-virtual-display
set -u

export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export XDG_RUNTIME_DIR=/run/user/1000
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0
export XAUTHORITY=$(systemctl --user show-environment 2>/dev/null | grep ^XAUTHORITY= | cut -d= -f2-)
export XDG_SESSION_TYPE=wayland

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/sunshine-display-backend.sh"

PHYS_FILE="$HOME/.local/share/sunshine-physical-outputs.list"
INHIBIT_PIDFILE="$HOME/.local/share/sunshine-inhibit.pid"

# --- 1. re-enable physical outputs ------------------------------------------
if [ -s "$PHYS_FILE" ]; then
    while read -r name; do
        [ -n "$name" ] && kscreen-doctor "output.$name.enable" >> "$LOG" 2>&1
    done < "$PHYS_FILE"
else
    # No record (e.g. a crash before the list was written): re-enable every
    # known non-virtual output so we never leave the machine blind, whatever
    # the physical output is named (DP-1, HDMI-A-1, HDMI-A-2, ...).
    kscreen-doctor -j | python3 -c "
import sys,json
for o in json.load(sys.stdin)['outputs']:
    if 'Virtual-' not in o['name']:
        print(o['name'])
" | while read -r name; do
        [ -n "$name" ] && kscreen-doctor "output.$name.enable" >> "$LOG" 2>&1
    done
fi
rm -f "$PHYS_FILE"
sleep 0.5

# --- 2. destroy the virtual -> KWin returns windows to the physical output --
destroy_virtual_display

# --- 3. release the idle/sleep inhibitor ------------------------------------
[ -f "$INHIBIT_PIDFILE" ] && kill "$(cat "$INHIBIT_PIDFILE")" 2>/dev/null
rm -f "$INHIBIT_PIDFILE"

log "disconnect: physical restored, virtual destroyed, inhibitor released"
