#!/usr/bin/env bash
# KDE autostart hook — locks the session immediately when a Plasma session starts.
#
# Paired with plasmalogin autologin: services (Sunshine, MoonDeckBuddy,
# joystick-notify) need graphical-session.target reached without a physical
# login, but autologin alone would hand anyone with physical access to the
# machine an already-open desktop. Locking immediately preserves the password
# as a real security boundary for local/physical access. Remote streaming is
# unaffected — couch-mode-screen-unlock.sh (wired into every Sunshine app's
# prep-cmd) already dismisses this lock automatically the instant a
# Moonlight/MoonDeck session connects.
#
# Install: sudo install -Dm0755 lock-on-login.sh /usr/local/bin/lock-on-login.sh

set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

LOG=/tmp/lock-on-login-debug.log
_log() { printf '[%s] lock-on-login: %s\n' "$(date '+%T')" "$*" >> "$LOG" 2>/dev/null || true; }

# Give ksld/logind a moment to be fully up before the session's first lock request.
sleep 2

_seat_session="$(loginctl 2>/dev/null | awk -v uid="$(id -u)" \
    'NR>1 && $2==uid && $4!="" && $4!="-" {print $1; exit}' || true)"
_log "seat session: '${_seat_session:-}'"

if [ -n "${_seat_session:-}" ]; then
    loginctl lock-session "$_seat_session" 2>/dev/null; rc=$?
    _log "loginctl lock-session: $rc"
else
    _log "no seat session found, falling back to ScreenSaver.Lock"
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.Lock 2>/dev/null; rc=$?
    _log "ScreenSaver.Lock: $rc"
fi
