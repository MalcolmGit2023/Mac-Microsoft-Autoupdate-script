#!/bin/bash
# Enhanced MAU updater with SwiftDialog/Jamf Helper deferrals, countdown, summaries, and graceful quit
LOG_FILE="/var/log/mau_update.log"
SUMMARY_DIR="/Library/Logs/BHG"; SUMMARY_FILE="$SUMMARY_DIR/mau_update_summary.txt"
STATE_DIR="/Library/Application Support/BHG/MAU"; STATE_FILE="$STATE_DIR/state.txt"
MAX_DEFERRALS=3; TIMER_SECONDS=300
DIALOG_BIN=""; JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
MAU_ICON="/Applications/Microsoft AutoUpdate.app/Contents/Resources/AppIcon.icns"
DEFAULT_APPS=(
  "com.microsoft.autoupdate" "com.microsoft.Word" "com.microsoft.Excel" "com.microsoft.Powerpoint" "com.microsoft.Outlook"
  "com.microsoft.onenote.mac" "com.microsoft.OneDrive" "com.microsoft.CompanyPortal" "com.microsoft.wdav" "com.microsoft.teams" "com.microsoft.Edge"
)
MS_PROCESSES=("Microsoft Word" "Microsoft Excel" "Microsoft PowerPoint" "Microsoft Outlook" "OneNote" "OneDrive" "Microsoft Teams" "Microsoft Defender" "Company Portal" "Microsoft Edge")

timestamp(){ date "+%Y-%m-%d %H:%M:%S"; }
log(){ echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }
ensure_dirs(){ mkdir -p "$SUMMARY_DIR" "$STATE_DIR"; chown root:wheel "$SUMMARY_DIR" "$STATE_DIR"; chmod 755 "$SUMMARY_DIR" "$STATE_DIR"; touch "$SUMMARY_FILE"; }
write_summary(){ ensure_dirs; echo "[$(timestamp)] $1 - $2" >> "$SUMMARY_FILE"; }
resolve_msupdate(){ local c=("/Applications/Microsoft AutoUpdate.app/Contents/MacOS/msupdate" "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"); for p in "${c[@]}"; do [[ -x "$p" ]] && echo "$p" && return 0; done; return 1; }
console_user(){ stat -f %Su /dev/console 2>/dev/null; }
run_as_user(){ local u="$1"; shift; local uid=$(id -u "$u" 2>/dev/null); [[ -n "$uid" ]] && launchctl asuser "$uid" "$@" || "$@"; }
detect_dialog(){ for d in "/usr/local/bin/dialog" "/usr/local/bin/swiftDialog"; do [[ -x "$d" ]] && DIALOG_BIN="$d" && return 0; done; return 1; }
load_state(){ DEFERRALS=0; LAST_PROMPT_EPOCH=0; [[ -f "$STATE_FILE" ]] && DEFERRALS=$(awk -F= '/^deferrals=/{print $2}' "$STATE_FILE"); }
save_state(){ cat > "$STATE_FILE" <<EOF
deferrals=${DEFERRALS}
last_prompt_epoch=$(date +%s)
EOF
chown root:wheel "$STATE_FILE"; chmod 644 "$STATE_FILE"; }
get_running(){ local r=(); for p in "${MS_PROCESSES[@]}"; do pgrep -fl "$p" >/dev/null 2>&1 && r+=("$p"); done; echo "${r[@]}"; }
quit_apps(){ local apps=("$@"); local u=$(console_user); for a in "${apps[@]}"; do log "Quit: $a"; if [[ -n "$u" ]]; then run_as_user "$u" osascript -e "tell application \"$a\" to quit"; else osascript -e "tell application \"$a\" to quit"; fi; sleep 2; done }

prompt_dialog(){ local title="$1"; local msg="$2"; local b1="$3"; local b2="$4"; local t="$5"; local u=$(console_user); local args=("--title" "$title" "--message" "$msg" "--icon" "$MAU_ICON" "--button1text" "$b1" "--button2text" "$b2" "--timer" "$t" "--quitkey" "esc" "--width" "560" "--height" "320"); if [[ -n "$u" ]]; then run_as_user "$u" "$DIALOG_BIN" "${args[@]}"; else "$DIALOG_BIN" "${args[@]}"; fi; return $? }
prompt_helper(){ local title="$1"; local msg="$2"; local b1="$3"; local b2="$4"; local t="$5"; local u=$(console_user); local args=(-windowType utility -title "$title" -description "$msg" -button1 "$b1" -button2 "$b2" -defaultButton 1 -timeout "$t" -icon "$MAU_ICON"); if [[ -n "$u" ]]; then run_as_user "$u" "$JAMF_HELPER" "${args[@]}"; else "$JAMF_HELPER" "${args[@]}"; fi; local rc=$?; [[ $rc -eq 0 ]] && return 0 || return 2 }
show_deferral(){ local list_text="$1"; local final="$2"; local title="Microsoft Updates Ready"; local now="Update Now"; local defer="Defer"; if [[ "$final" == "true" ]]; then local msg="Updates are available. Deferrals exhausted. This update is required now.\n\nApps to close:\n${list_text}"; if detect_dialog; then local u=$(console_user); local args=("--title" "$title" "--message" "$msg" "--icon" "$MAU_ICON" "--button1text" "$now" "--timer" "120" "--quitkey" "disabled" "--width" "560" "--height" "320"); [[ -n "$u" ]] && run_as_user "$u" "$DIALOG_BIN" "${args[@]}" || "$DIALOG_BIN" "${args[@]}"; return $?; else local u=$(console_user); local args=(-windowType utility -title "$title" -description "$msg" -button1 "$now" -defaultButton 1 -timeout 120 -icon "$MAU_ICON"); [[ -n "$u" ]] && run_as_user "$u" "$JAMF_HELPER" "${args[@]}" || "$JAMF_HELPER" "${args[@]}"; local rc=$?; [[ $rc -eq 0 ]] && return 0 || return 2; fi; else local msg="Updates are available for Microsoft apps.\n\nApps to close:\n${list_text}\n\nYou can defer ${MAX_DEFERRALS} times. Used: ${DEFERRALS}. A ${TIMER_SECONDS}s countdown is running."; if detect_dialog; then prompt_dialog "$title" "$msg" "$now" "$defer" "$TIMER_SECONDS"; local rc=$?; [[ $rc -eq 0 ]] && return 0 || return 2; else prompt_helper "$title" "$msg" "$now" "$defer" "$TIMER_SECONDS"; local rc=$?; [[ $rc -eq 0 ]] && return 0 || return 2; fi; fi }

open_mau(){ command -v open >/dev/null && open -a "Microsoft AutoUpdate" 2>/dev/null && log "Opened MAU."; }
parse_csv(){ IFS=',' read -r -a arr <<< "$1"; echo "${arr[@]}"; }

SHOW_HELP=false; DO_OPEN=false; DO_LIST=false; DO_INSTALL=false; USE_ALL=false; CUSTOM_APPS=()
while [[ $# -gt 0 ]]; do case "$1" in
  --help|-h) SHOW_HELP=true; shift;;
  --open) DO_OPEN=true; shift;;
  --list|--scan) DO_LIST=true; shift;;
  --install) DO_INSTALL=true; shift;;
  --all) USE_ALL=true; shift;;
  --apps) [[ -n "$2" ]] || { echo "--apps requires list"; exit 2; }; CUSTOM_APPS=($(parse_csv "$2")); shift 2;;
  --timer) [[ -n "$2" ]] || { echo "--timer requires seconds"; exit 2; }; TIMER_SECONDS="$2"; shift 2;;
  --max-deferrals) [[ -n "$2" ]] || { echo "--max-deferrals requires number"; exit 2; }; MAX_DEFERRALS="$2"; shift 2;;
  *) log "WARN: Unknown arg $1"; shift;;
done; done

$SHOW_HELP && { cat <<EOF
Usage: mau_update_swiftdialog.sh [--open] [--list|--scan] [--install] [--all|--apps csv] [--timer secs] [--max-deferrals n]
EOF
exit 0; }

[[ "$DO_OPEN" = false && "$DO_LIST" = false && "$DO_INSTALL" = false ]] && DO_LIST=true
ensure_dirs
MSU="$(resolve_msupdate)" || { log "ERROR: msupdate not found"; write_summary "Error" "msupdate not found"; exit 1; }
log "Using msupdate at: $MSU"
TARGET=(); $USE_ALL && TARGET=("${DEFAULT_APPS[@]}")
[[ ${#CUSTOM_APPS[@]} -gt 0 ]] && TARGET=($(printf "%s\n" "${TARGET[@]}" "${CUSTOM_APPS[@]}" | awk '!seen[$0]++'))
$DO_INSTALL && [[ ${#TARGET[@]} -eq 0 ]] && TARGET=("${DEFAULT_APPS[@]}")

$DO_OPEN && open_mau
if $DO_LIST; then $MSU --list | tee -a "$LOG_FILE" && write_summary "Scan" "msupdate --list completed" || { write_summary "Error" "msupdate --list failed"; [[ $DO_INSTALL == false ]] && exit 4; }; fi

if $DO_INSTALL; then load_state; local apps=("$(get_running)"); local list_text=""; if [[ -n "$apps" ]]; then for a in $apps; do list_text+="- ${a}\n"; done; else list_text="- (none detected)\n"; fi
  if [[ "$DEFERRALS" -lt "$MAX_DEFERRALS" ]]; then show_deferral "$list_text" "false"; local choice=$?; if [[ $choice -eq 0 ]]; then write_summary "User Choice" "Update Now (${DEFERRALS}/${MAX_DEFERRALS})"; [[ -n "$apps" ]] && quit_apps $apps; else DEFERRALS=$((DEFERRALS+1)); save_state; write_summary "User Choice" "Deferred (${DEFERRALS}/${MAX_DEFERRALS})"; log "User deferred (${DEFERRALS}/${MAX_DEFERRALS})"; exit 5; fi
  else show_deferral "$list_text" "true"; write_summary "User Choice" "Final prompt (no deferral)"; [[ -n "$apps" ]] && quit_apps $apps; fi
  APP_CSV=$(IFS=','; echo "${TARGET[*]}"); write_summary "Install Start" "Apps=${APP_CSV}"; log "Installing: $APP_CSV";
  $MSU --install --apps "$APP_CSV" --wait | tee -a "$LOG_FILE" && write_summary "Install Complete" "Apps=${APP_CSV}" || { write_summary "Install Retry" "--force"; $MSU --install --apps "$APP_CSV" --wait --force | tee -a "$LOG_FILE" && write_summary "Install Complete" "Second attempt" || { write_summary "Error" "Install failed"; exit 3; } }
fi
write_summary "Script Complete" "mau_update_swiftdialog.sh finished"; log "Done."; exit 0
