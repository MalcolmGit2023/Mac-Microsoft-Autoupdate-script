#!/bin/bash
# Minimal MAU updater: open GUI (optional), list, and install via msupdate
LOG_FILE="/var/log/mau_update.log"
DEFAULT_APPS=(
  "com.microsoft.autoupdate"
  "com.microsoft.Word" "com.microsoft.Excel" "com.microsoft.Powerpoint" "com.microsoft.Outlook"
  "com.microsoft.onenote.mac" "com.microsoft.OneDrive" "com.microsoft.CompanyPortal" "com.microsoft.wdav"
  "com.microsoft.teams" "com.microsoft.Edge"
)

timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }
resolve_msupdate(){
  local c=(
    "/Applications/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
    "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
  ); for p in "${c[@]}"; do [[ -x "$p" ]] && echo "$p" && return 0; done; return 1;
}
open_mau(){ command -v open >/dev/null && open -a "Microsoft AutoUpdate" 2>/dev/null && log "Opened MAU."; }
parse_csv(){ IFS=',' read -r -a arr <<< "$1"; echo "${arr[@]}"; }

SHOW_HELP=false; DO_OPEN=false; DO_LIST=false; DO_INSTALL=false; USE_ALL=false; CUSTOM_APPS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --help|-h) SHOW_HELP=true; shift;;
  --open) DO_OPEN=true; shift;;
  --list|--scan) DO_LIST=true; shift;;
  --install) DO_INSTALL=true; shift;;
  --all) USE_ALL=true; shift;;
  --apps) [[ -n "$2" ]] || { log "ERROR: --apps requires list"; exit 2; }; CUSTOM_APPS=($(parse_csv "$2")); shift 2;;
  *) log "WARN: Unknown arg $1"; shift;;
done; done

$SHOW_HELP && {
cat <<EOF
Usage: mau_update_basic.sh [--open] [--list|--scan] [--install] [--all|--apps csv]
EOF
exit 0; }

[[ "$DO_OPEN" = false && "$DO_LIST" = false && "$DO_INSTALL" = false ]] && DO_LIST=true
MSU="$(resolve_msupdate)" || { log "ERROR: msupdate not found"; exit 1; }
log "Using msupdate at: $MSU"
TARGET=(); $USE_ALL && TARGET=("${DEFAULT_APPS[@]}")
[[ ${#CUSTOM_APPS[@]} -gt 0 ]] && TARGET=($(printf "%s\n" "${TARGET[@]}" "${CUSTOM_APPS[@]}" | awk '!seen[$0]++'))
$DO_INSTALL && [[ ${#TARGET[@]} -eq 0 ]] && TARGET=("${DEFAULT_APPS[@]}")

$DO_OPEN && open_mau
if $DO_LIST; then $MSU --list | tee -a "$LOG_FILE" || { log "ERROR: list failed"; [[ $DO_INSTALL == false ]] && exit 4; }; fi
if $DO_INSTALL; then APP_CSV=$(IFS=','; echo "${TARGET[*]}");
  $MSU --install --apps "$APP_CSV" --wait | tee -a "$LOG_FILE" || { log "ERROR: install failed"; $MSU --install --apps "$APP_CSV" --wait --force | tee -a "$LOG_FILE" || exit 3; }
fi
log "Done."; exit 0
