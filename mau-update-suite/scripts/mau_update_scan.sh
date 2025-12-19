#!/bin/bash
# Lightweight MAU scanner for inventory jobs
LOG_FILE="/var/log/mau_update.log"

timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }
resolve_msupdate(){ for p in "/Applications/Microsoft AutoUpdate.app/Contents/MacOS/msupdate" "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"; do [[ -x "$p" ]] && echo "$p" && return 0; done; return 1; }

MSU="$(resolve_msupdate)" || { log "ERROR: msupdate not found"; exit 1; }
log "Using msupdate at: $MSU"
$MSU --list | tee -a "$LOG_FILE" || { log "ERROR: list failed"; exit 4; }
log "Scan complete"; exit 0
