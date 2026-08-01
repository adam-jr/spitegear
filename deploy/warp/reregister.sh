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
# Posts a success/failure line to Slack (#spitegear_alerts, same channel
# used for cookie-refresh confirmations) via the running spitegear
# container's rpc console, so runs are visible without SSHing in.
#
# Usage (crontab, America/Chicago system time):
#   15 3 * * * /path/to/spitegear/deploy/warp/reregister.sh >> /path/to/spitegear/warp-reregister.log 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

slack() {
  docker exec spitegear bin/spitegear rpc \
    "Spitegear.PubSub.msg(:spitegear_alerts, \"$1\")" >/dev/null 2>&1
}

log "re-registering warp"

# Best-effort: these can no-op or fail harmlessly if warp is already
# disconnected / has no registration (e.g. first run).
docker exec warp warp-cli disconnect >/dev/null 2>&1
docker exec warp warp-cli registration delete >/dev/null 2>&1

if ! docker exec warp warp-cli registration new; then
  log "registration new FAILED"
  slack ":x: warp re-registration failed: \`registration new\` errored. Check warp-reregister.log on the Beelink."
  exit 1
fi

if ! docker exec warp warp-cli connect; then
  log "connect FAILED"
  slack ":x: warp re-registration failed: \`connect\` errored after a fresh registration. Check warp-reregister.log on the Beelink."
  exit 1
fi

sleep 5
status=$(docker exec warp warp-cli status)
log "status: $status"

case "$status" in
  *Connected*)
    # Check through the GOST relay on :1080 (the same port privoxy forwards
    # through) rather than a bare curl from inside the container — warp-cli
    # runs in WarpProxy mode here, so only traffic sent through that port is
    # actually tunneled. Best-effort: don't fail the run if this lookup fails.
    egress_ip=$(docker exec warp curl -fsS -x socks5h://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace 2>/dev/null | grep '^ip=' | cut -d= -f2)
    log "re-registration succeeded, egress IP: ${egress_ip:-unknown}"
    slack ":white_check_mark: warp re-registered and reconnected, egress IP rotated to \`${egress_ip:-unknown}\`."
    ;;
  *)
    log "WARNING: warp not connected after re-registration"
    slack ":x: warp re-registration finished but is not connected afterward. Check warp-reregister.log on the Beelink."
    exit 1
    ;;
esac
