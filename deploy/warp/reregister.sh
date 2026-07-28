#!/bin/sh
# Re-registers the `warp` sidecar as a fresh anonymous Cloudflare device,
# which changes its egress IP (identity is randomly reassigned by
# Cloudflare; the proxy-mode setting itself persists across a
# delete/new cycle, so it does not need to be re-applied here).
#
# Intended to run on a daily cron, timed for the middle of the night —
# inside the app's existing overnight poll-pause window (midnight-7am
# America/Chicago, see GamePoller's night?/0) — so it never runs while
# a wargear.net request could be in flight.
#
# Usage (crontab, America/Chicago system time):
#   15 3 * * * /path/to/spitegear/deploy/warp/reregister.sh >> /path/to/spitegear/warp-reregister.log 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

log "re-registering warp"

# Best-effort: these can no-op or fail harmlessly if warp is already
# disconnected / has no registration (e.g. first run).
docker exec warp warp-cli disconnect >/dev/null 2>&1
docker exec warp warp-cli registration delete >/dev/null 2>&1

if ! docker exec warp warp-cli registration new; then
  log "registration new FAILED"
  exit 1
fi

if ! docker exec warp warp-cli connect; then
  log "connect FAILED"
  exit 1
fi

sleep 5
status=$(docker exec warp warp-cli status)
log "status: $status"

case "$status" in
  *Connected*)
    log "re-registration succeeded"
    ;;
  *)
    log "WARNING: warp not connected after re-registration"
    exit 1
    ;;
esac
