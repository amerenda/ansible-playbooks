#!/usr/bin/env bash
# capture-edid.sh — capture, validate, and base64-encode a DRM connector's
# live EDID for use as a roles/hardware-tweaks host_vars override entry.
#
# Usage:
#   capture-edid.sh <connector> [output-file]
#   capture-edid.sh --wait [--timeout SECONDS] <connector> [output-file]
#
#   connector    DRM connector name as it appears under /sys/class/drm/,
#                without the cardN- prefix, e.g. HDMI-A-1, DP-2. List
#                candidates with: ls /sys/class/drm/ | grep -v 'card.$'
#   output-file  where to write the raw captured EDID (default: ./<connector>.bin)
#   --wait       poll until the connector reports "connected" with a
#                non-empty EDID instead of failing immediately. Use this
#                for hardware where the real sink only negotiates DDC for a
#                narrow window (see the capture-window note this script is
#                documented alongside in Projects/Joystick-Notify/notes/
#                edid-override-generalization-background.md).
#   --timeout    seconds to poll for with --wait (default: 60)
#
# Run on the host with the hardware attached — locally, or piped over SSH:
#   ssh <host> 'bash -s' -- HDMI-A-1 < capture-edid.sh
#
# Requires: sudo (reading /sys/class/drm/*/edid and /sys/kernel/debug/dri/
# is root-only on most distro kernels), edid-decode (pacman -S edid-decode)
# for full validation — the size/multiple-of-128 check still runs without it.

set -euo pipefail

wait_mode=false
timeout=60
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wait) wait_mode=true; shift ;;
    --timeout) timeout="${2:?--timeout needs a value}"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- "${args[@]}"

connector="${1:?usage: capture-edid.sh [--wait] [--timeout SECONDS] <connector> [output-file]}"
out="${2:-./${connector}.bin}"

class_dir=""
for d in /sys/class/drm/card*-"${connector}"; do
  [ -d "$d" ] && class_dir="$d" && break
done
if [ -z "$class_dir" ]; then
  echo "error: no /sys/class/drm/card*-${connector} found -- check the connector name with: ls /sys/class/drm/ | grep -v 'card.\$'" >&2
  exit 1
fi
card_name="$(basename "$class_dir" | sed "s/-${connector}\$//")"
echo "Found connector: $class_dir (${card_name})"

status_file="$class_dir/status"
edid_file="$class_dir/edid"

check_ready() {
  local status size
  status="$(cat "$status_file" 2>/dev/null || echo unknown)"
  size="$(sudo cat "$edid_file" 2>/dev/null | wc -c || echo 0)"
  echo "$status $size"
}

if $wait_mode; then
  echo "Waiting up to ${timeout}s for '${connector}' to report connected with a non-empty EDID..."
  echo "(reseat the cable / power-cycle the downstream device now if it doesn't come up on its own)"
  elapsed=0
  while true; do
    read -r status size <<<"$(check_ready)"
    if [ "$status" = "connected" ] && [ "$size" -gt 0 ]; then
      echo "Connected, EDID present (${size} bytes) after ${elapsed}s."
      break
    fi
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "error: timed out after ${timeout}s waiting for '${connector}' (last status: ${status}, edid size: ${size})" >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
else
  status="$(cat "$status_file" 2>/dev/null || echo unknown)"
  echo "Connector status: $status"
  if [ "$status" != "connected" ]; then
    echo "warning: connector reports '$status', not 'connected' -- capture may be empty or stale. Re-run with --wait to poll for the window, or reseat the cable / power-cycle the downstream device first." >&2
  fi
fi

size="$(sudo cat "$edid_file" 2>/dev/null | wc -c || echo 0)"
if [ "$size" -eq 0 ]; then
  echo "error: $edid_file is empty -- connector isn't presenting an EDID right now. Try --wait." >&2
  exit 1
fi

sudo cat "$edid_file" > "$out"
actual_size="$(wc -c < "$out")"
echo "Captured $actual_size bytes to $out"

if [ $(( actual_size % 128 )) -ne 0 ]; then
  echo "error: captured EDID size (${actual_size} bytes) is not a multiple of 128 -- likely truncated/corrupt capture" >&2
  exit 1
fi

if ! command -v edid-decode >/dev/null 2>&1; then
  echo "warning: edid-decode not installed (pacman -S edid-decode) -- skipping header/checksum validation" >&2
else
  decode_out="${out}.decode.txt"
  if ! edid-decode "$out" > "$decode_out" 2>&1; then
    echo "error: edid-decode reported problems -- see $decode_out" >&2
    exit 1
  fi
  if grep -qi "Checksum: Invalid" "$decode_out"; then
    echo "error: EDID checksum invalid -- see $decode_out" >&2
    exit 1
  fi
  echo "edid-decode validation OK -- see $decode_out for manufacturer/model, extension blocks, CEA/HDMI VSDB physical address, etc."
fi

debugfs_index=""
if sudo test -d /sys/kernel/debug/dri; then
  # A plain shell glob can't expand this -- debugfs/dri is root-only, so
  # listing it (not just reading files under it) needs sudo too.
  for n in $(sudo ls /sys/kernel/debug/dri/ 2>/dev/null); do
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if sudo test -d "/sys/kernel/debug/dri/${n}/${connector}"; then
      debugfs_index="$n"
      break
    fi
  done
fi
if [ -z "$debugfs_index" ]; then
  echo "warning: could not find /sys/kernel/debug/dri/N/${connector} -- is debugfs mounted? (mount | grep debugfs). This index is needed for the edid_override host_vars entry (drm_card_index)." >&2
else
  echo "debugfs override target: /sys/kernel/debug/dri/${debugfs_index}/${connector}/edid_override  (drm_card_index: ${debugfs_index})"
fi

echo
echo "── base64 for host_vars (edid_<name>: >-) ──"
base64 -w76 "$out"
