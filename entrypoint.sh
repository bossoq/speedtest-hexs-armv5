#!/bin/sh
# Periodic Ookla speedtest -> InfluxDB 2 line protocol, for the NK hEX S (source=mikrotik).
# Matches CT108's measurement "speedtest" (fields download_mbps/upload_mbps/ping_ms/
# jitter_ms/packet_loss; tags site,server_id) and adds tag source=mikrotik.
set -u
INFLUX_URL="${INFLUX_URL:?INFLUX_URL required}"
INFLUX_TOKEN="${INFLUX_TOKEN:?INFLUX_TOKEN required}"
INFLUX_ORG="${INFLUX_ORG:-Picturous}"
INFLUX_BUCKET="${INFLUX_BUCKET:-Proxmox}"
SITE="${SITE:-nongkhaem}"
SOURCE="${SOURCE:-mikrotik}"
SERVER_ID="${SERVER_ID:-16063}"
INTERVAL="${INTERVAL:-21600}"   # 6h
STARTUP_DELAY="${STARTUP_DELAY:-20}"

mbps() { awk -v b="${1:-0}" 'BEGIN{ if(b=="")b=0; printf "%.2f", b*8/1000000 }'; }
jnum() { printf '%s' "$1" | sed -n "s/.*\"$2\":\([0-9.][0-9.]*\).*/\1/p"; }

sleep "$STARTUP_DELAY"   # let the container's network settle before first run
while true; do
  J="$(timeout 150 speedtest --server-id="$SERVER_ID" --accept-license --accept-gdpr --format=json --progress=no 2>/dev/null)"
  if [ -n "$J" ] && printf '%s' "$J" | grep -q '"type":"result"'; then
    # download/upload bandwidth are bytes/sec in Ookla JSON
    dlb="$(printf '%s' "$J" | sed -n 's/.*"download":{"bandwidth":\([0-9]*\).*/\1/p')"
    ulb="$(printf '%s' "$J" | sed -n 's/.*"upload":{"bandwidth":\([0-9]*\).*/\1/p')"
    lat="$(printf '%s' "$J" | sed -n 's/.*"ping":{"jitter":[0-9.]*,"latency":\([0-9.]*\).*/\1/p')"
    jit="$(printf '%s' "$J" | sed -n 's/.*"ping":{"jitter":\([0-9.]*\).*/\1/p')"
    pl="$(jnum "$J" packetLoss)"; [ -z "$pl" ] && pl=0
    dl="$(mbps "$dlb")"; ul="$(mbps "$ulb")"
    [ -z "$lat" ] && lat=0; [ -z "$jit" ] && jit=0
    LINE="speedtest,site=${SITE},source=${SOURCE},server_id=${SERVER_ID} download_mbps=${dl},upload_mbps=${ul},ping_ms=${lat},jitter_ms=${jit},packet_loss=${pl}"
    if wget -q -O- \
        --header="Authorization: Token ${INFLUX_TOKEN}" \
        --header="Content-Type: text/plain; charset=utf-8" \
        --post-data="$LINE" \
        "${INFLUX_URL}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}&precision=s" >/dev/null 2>&1; then
      echo "$(date -u +%FT%TZ) pushed: $LINE"
    else
      echo "$(date -u +%FT%TZ) push FAILED (influx unreachable?): $LINE"
    fi
  else
    echo "$(date -u +%FT%TZ) speedtest produced no result (CPU/network?)"
  fi
  sleep "$INTERVAL"
done
