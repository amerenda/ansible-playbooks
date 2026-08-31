#!/bin/bash
# llama-watchdog — stall detector for murderbot
#
# Restarts the llama-server Docker container if a slot has been occupied
# with no new tokens for STALL_TIMEOUT_S (catches the PR #22907 cascade
# and other hung-inference states).
#
# VRAM-threshold restarts were removed 2026-08-31: that check existed to
# protect Jellyfin NVENC transcoding headroom, but Jellyfin no longer uses
# this GPU for transcoding, and the check was incompatible with the
# qwen36 profile's 98,304-context footprint (~421 MiB free once loaded,
# under the old 800 MiB threshold), which put llama-server in a permanent
# crash-restart loop.
#
# Runs as a systemd service. See llama-watchdog.service.
# Deployed via ansible-playbooks/playbooks/infrastructure/setup-debian-komodo.yml
# (tags: debian-komodo, debian-llama-watchdog).

CONTAINER=llama-server
STALL_TIMEOUT_S=300       # Restart if no new tokens for 5 min while slot busy
CHECK_INTERVAL_S=30       # Poll interval
COOLDOWN_S=180            # Minimum seconds between restarts
METRICS_URL=http://127.0.0.1:8088/metrics

LAST_RESTART=0
LAST_TOKENS_TOTAL=""
LAST_TOKENS_TIME=0

log() {
    echo "$(date -Iseconds) llama-watchdog: $*"
    logger -t llama-watchdog "$*" 2>/dev/null || true
}

get_metric() {
    local name="$1"
    curl -sf --max-time 5 "$METRICS_URL" 2>/dev/null \
        | awk -v n="^${name} " '$0 ~ n {print $2; exit}'
}

restart_container() {
    local reason="$1"
    local now; now=$(date +%s)
    if (( now - LAST_RESTART < COOLDOWN_S )); then
        log "SKIP restart (${COOLDOWN_S}s cooldown): $reason"
        return 1
    fi
    log "RESTART: $reason"
    docker restart "$CONTAINER" 2>&1 | while IFS= read -r line; do log "docker: $line"; done
    LAST_RESTART=$(date +%s)
    LAST_TOKENS_TOTAL=""
    LAST_TOKENS_TIME=0
    return 0
}

log "starting (container=$CONTAINER, stall=${STALL_TIMEOUT_S}s)"

while true; do
    sleep "$CHECK_INTERVAL_S"

    # ── Stall detection ──────────────────────────────────────────────────────
    requests=$(get_metric "llamacpp:requests_processing")
    tokens=$(get_metric "llamacpp:tokens_predicted_total")
    now=$(date +%s)

    if [[ "$requests" =~ ^[0-9]+$ && "$requests" -gt 0 && -n "$tokens" ]]; then
        if [[ "$tokens" != "$LAST_TOKENS_TOTAL" ]]; then
            # Progress: tokens are being generated
            LAST_TOKENS_TOTAL="$tokens"
            LAST_TOKENS_TIME="$now"
        elif [[ "$LAST_TOKENS_TIME" -gt 0 ]] && (( now - LAST_TOKENS_TIME > STALL_TIMEOUT_S )); then
            stall_s=$(( now - LAST_TOKENS_TIME ))
            restart_container "inference stall: slot occupied, no new tokens for ${stall_s}s"
        fi
    else
        # No active slot — reset stall timer
        LAST_TOKENS_TIME=0
    fi
done
