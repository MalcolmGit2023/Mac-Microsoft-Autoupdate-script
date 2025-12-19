
#!/bin/bash
#
# mau_update.sh
# Purpose: Open Microsoft AutoUpdate GUI and run msupdate to scan/list/install updates on macOS.
#          Includes: countdown + deferral via SwiftDialog/Jamf Helper, human-readable summaries,
#          state tracking (deferral count), and graceful app-quit workflow.
# 
#
# Exit codes:
#  0 = success
#  1 = msupdate not found
#  2 = invalid arguments
#  3 = install operation failed
#  4 = list/scan operation failed
#  5 = user deferred
#  6 = no GUI session detected (optional soft failure)
#

### -------- Settings (tweak as needed) --------
LOG_FILE="/var/log/mau_update.log"
SUMMARY_DIR="/Library/Logs"
SUMMARY_FILE="${SUMMARY_DIR}/mau_update_summary.txt"

STATE_DIR="/Library/Application Support/MS/MAU"
STATE_FILE="${STATE_DIR}/state.txt"

# Max deferrals allowed before forcing update
MAX_DEFERRALS=3

# Countdown presented to users (in seconds)
TIMER_SECONDS=300   # 5 minutes

# SwiftDialog / Jamf Helper paths
DIALOG_BIN=""  # resolved dynamically
JAMF_HELPER="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Icon used in dialogs (fallback to MAU icon)
MAU_ICON="/Applications/Microsoft AutoUpdate.app/Contents/Resources/AppIcon.icns"

# Default app IDs (extend as needed)
DEFAULT_APPS=(
  "com.microsoft.autoupdate"
  "com.microsoft.Word"
  "com.microsoft.Excel"
  "com.microsoft.Powerpoint"
  "com.microsoft.Outlook"
  "com.microsoft.onenote.mac"
  "com.microsoft.OneDrive"
  "com.microsoft.CompanyPortal"
  "com.microsoft.wdav"
  "com.microsoft.teams"      # classic Teams
  "com.microsoft.Edge"       # support varies
)

# Process names to look for
MS_PROCESSES=(
  "Microsoft Word"
  "Microsoft Excel"
  "Microsoft PowerPoint"
  "Microsoft Outlook"
  "OneNote"
  "OneDrive"
  "Microsoft Teams"
  "Microsoft Defender"
  "Company Portal"
  "Microsoft Edge"
)

### -------- Utilities --------
timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log()       { echo "[$(timestamp)] $*" | tee -a "$LOG_FILE"; }

ensure_dirs() {
  /bin/mkdir -p "$SUMMARY_DIR" "$STATE_DIR"
  /usr/sbin/chown root:wheel "$SUMMARY_DIR" "$STATE_DIR"
  /bin/chmod 755 "$SUMMARY_DIR" "$STATE_DIR"
  touch "$SUMMARY_FILE"
}

write_summary() {
  # $1 = event, $2 = detail
  ensure_dirs
  echo "[$(timestamp)] $1 - $2" >> "$SUMMARY_FILE"
}

resolve_msupdate() {
  local candidates=(
    "/Applications/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
    "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
  )
  for p in "${candidates[@]}"; do
    [[ -x "$p" ]] && echo "$p" && return 0
  done
  return 1
}

current_console_user() {
  # returns username or empty
  /usr/bin/stat -f %Su /dev/console 2>/dev/null
}

run_as_user() {
  local user="$1"; shift
  local uid
  uid=$(/usr/bin/id -u "$user" 2>/dev/null)
  if [[ -n "$uid" ]]; then
    /bin/launchctl asuser "$uid" "$@"
  else
    "$@"
  fi
}

detect_dialog() {
  local candidates=(
    "/usr/local/bin/dialog"        # SwiftDialog 2.x+
    "/usr/local/bin/swiftDialog"   # legacy
  )
  for d in "${candidates[@]}"; do
    if [[ -x "$d" ]]; then DIALOG_BIN="$d"; return 0; fi
  done
  return 1
}

load_state() {
  # defaults
  DEFERRALS=0
  LAST_PROMPT_EPOCH=0

  if [[ -f "$STATE_FILE" ]]; then
    DEFERRALS=$(awk -F= '/^deferrals=/{print $2}' "$STATE_FILE")
    LAST_PROMPT_EPOCH=$(awk -F= '/^last_prompt_epoch=/{print $2}' "$STATE_FILE")
  fi
}

save_state() {
  cat > "$STATE_FILE" <<EOF
deferrals=${DEFERRALS}
last_prompt_epoch=$(date +%s)
EOF
  /usr/sbin/chown root:wheel "$STATE_FILE"
  /bin/chmod 644 "$STATE_FILE"
}

get_running_ms_apps() {
  local running=()
  for proc in "${MS_PROCESSES[@]}"; do
    if /usr/bin/pgrep -fl "$proc" >/dev/null 2>&1; then
      running+=("$proc")
    fi
  done
  echo "${running[@]}"
}

quit_apps_gracefully() {
  local apps=("$@")
  local user="$(current_console_user)"
  for a in "${apps[@]}"; do
    log "Attempting graceful quit: $a"
    if [[ -n "$user" ]]; then
      run_as_user "$user" /usr/bin/osascript <<OSA
try
  tell application "$a" to quit
end try
OSA
    else
      /usr/bin/osascript <<OSA
try
  tell application "$a" to quit
end try
OSA
    fi
    sleep 2
  done
}

prompt_swiftdialog() {
  local title="$1"; shift
  local message="$1"; shift
  local button1="$1"; shift
  local button2="$1"; shift
  local timer="$1"; shift

  local user="$(current_console_user)"
  local args=(
    "--title" "$title"
    "--message" "$message"
    "--icon" "$MAU_ICON"
    "--button1text" "$button1"
    "--button2text" "$button2"
    "--timer" "$timer"
    "--quitkey" "esc"         # ESC defers
    "--width" "560"
    "--height" "320"
  )

  if [[ -n "$user" ]]; then
    run_as_user "$user" "$DIALOG_BIN" "${args[@]}"
  else
    "$DIALOG_BIN" "${args[@]}"
  fi
  return $?
}

prompt_jamfhelper() {
  local title="$1"; shift
  local message="$1"; shift
  local button1="$1"; shift
  local button2="$1"; shift
  local timer="$1"; shift

  local user="$(current_console_user)"
  local args=(
    -windowType utility
    -title "$title"
    -description "$message"
    -button1 "$button1"
    -button2 "$button2"
    -defaultButton 1
    -timeout "$timer"
    -icon "$MAU_ICON"
  )
  if [[ -n "$user" ]]; then
    run_as_user "$user" "$JAMF_HELPER" "${args[@]}"
  else
    "$JAMF_HELPER" "${args[@]}"
  fi
  # jamfHelper: 0=button1, 2=button2, 5=timeout (treated as defer)
  local rc=$?
  [[ "$rc" -eq 0 ]] && return 0 || return 2
}

show_deferral_dialog() {
  # returns 0 if "Update Now", non-zero for "Defer"
  local apps_list_text="$1"; shift
  local is_final="$1"; shift   # "true" or "false"

  local title="Microsoft Updates Ready"
  local button_now="Update Now"
  local button_defer="Defer"
  local timer="$TIMER_SECONDS"

  local msg_base="Updates are available for Microsoft apps.\n\nThe following apps should be closed before installation:\n${apps_list_text}\n\nPlease save your work."
  local message

  if [[ "$is_final" == "true" ]]; then
    message="${msg_base}\n\nDeferrals exhausted (max: ${MAX_DEFERRALS}). This update is required now."
    # In final prompt, remove deferral button and shorten timer
    if detect_dialog; then
      local user="$(current_console_user)"
      local args=(
        "--title" "$title"
        "--message" "$message"
        "--icon" "$MAU_ICON"
        "--button1text" "$button_now"
        "--timer" "120"
        "--quitkey" "disabled"
        "--width" "560"
        "--height" "320"
      )
      if [[ -n "$user" ]]; then
        run_as_user "$user" "$DIALOG_BIN" "${args[@]}"
      else
        "$DIALOG_BIN" "${args[@]}"
      fi
      return $?
    else
      # Jamf Helper without button2 to enforce action
      local user="$(current_console_user)"
      local args=(
        -windowType utility
        -title "$title"
        -description "$message"
        -button1 "$button_now"
        -defaultButton 1
        -timeout 120
        -icon "$MAU_ICON"
      )
      if [[ -n "$user" ]]; then
        run_as_user "$user" "$JAMF_HELPER" "${args[@]}"
      else
        "$JAMF_HELPER" "${args[@]}"
      fi
      local rc=$?
      [[ "$rc" -eq 0 ]] && return 0 || return 2
    fi
  else
    message="${msg_base}\n\nYou can defer ${MAX_DEFERRALS} times. Current deferrals used: ${DEFERRALS}.\nA ${TIMER_SECONDS}s countdown is running; choose “Update Now” to proceed or “Defer” to postpone."
    if detect_dialog; then
      prompt_swiftdialog "$title" "$message" "$button_now" "$button_defer" "$timer"
      local rc=$?
      # SwiftDialog convention: 0=button1; non-zero (button2/esc/close) => defer
      [[ "$rc" -eq 0 ]] && return 0 || return 2
    else
      prompt_jamfhelper "$title" "$message" "$button_now" "$button_defer" "$timer"
      local rc=$?
      [[ "$rc" -eq 0 ]] && return 0 || return 2
    fi
  fi
}

open_mau_gui() {
  if command -v open >/dev/null 2>&1; then
    open -a "Microsoft AutoUpdate" 2>/dev/null && log "Opened MAU GUI." || log "GUI open failed or app absent."
  fi
}

parse_apps_csv() {
  local csv="$1"
  IFS=',' read -r -a parsed <<< "$csv"
  echo "${parsed[@]}"
}

### -------- Argument parsing --------
SHOW_HELP=false
DO_OPEN=false
DO_LIST=false
DO_INSTALL=false
USE_ALL=false
CUSTOM_APPS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) SHOW_HELP=true; shift ;;
    --open) DO_OPEN=true; shift ;;
    --list|--scan) DO_LIST=true; shift ;;
    --install) DO_INSTALL=true; shift ;;
    --all) USE_ALL=true; shift ;;
    --apps)
      [[ -n "$2" ]] || { log "ERROR: --apps requires comma-separated IDs."; exit 2; }
      CUSTOM_APPS=($(parse_apps_csv "$2")); shift 2 ;;
    --timer)
      [[ -n "$2" ]] || { log "ERROR: --timer requires seconds."; exit 2; }
      TIMER_SECONDS="$2"; shift 2 ;;
    --max-deferrals)
      [[ -n "$2" ]] || { log "ERROR: --max-deferrals requires a number."; exit 2; }
      MAX_DEFERRALS="$2"; shift 2 ;;
    *)
      log "WARN: Unrecognized argument: $1"; shift ;;
  esac
done

if $SHOW_HELP; then
  cat <<'EOF'
Microsoft AutoUpdate helper

Options:
  --open               Open the Microsoft AutoUpdate GUI (user-facing)
  --list|--scan        Scan and list available updates via msupdate
  --install            Install updates for selected apps (with deferral prompts)
  --all                Use the default built-in set of Microsoft app IDs
  --apps <csv>         Comma-separated app IDs (overrides/supplements defaults)
  --timer <seconds>    Countdown (default: 300)
  --max-deferrals <n>  Max deferrals allowed (default: 3)
  -h|--help            Show this help
EOF
  exit 0
fi

if ! $DO_OPEN && ! $DO_LIST && ! $DO_INSTALL; then
  log "INFO: No action specified. Defaulting to --list."
  DO_LIST=true
fi

ensure_dirs
MSUPDATE_BIN="$(resolve_msupdate)"
if [[ -z "$MSUPDATE_BIN" ]]; then
  log "ERROR: 'msupdate' not found. Ensure Microsoft AutoUpdate is installed."
  write_summary "Error" "msupdate not found"
  exit 1
fi
log "Using msupdate at: $MSUPDATE_BIN"

TARGET_APPS=()
$USE_ALL && TARGET_APPS=("${DEFAULT_APPS[@]}")
if [[ ${#CUSTOM_APPS[@]} -gt 0 ]]; then
  TARGET_APPS=($(printf "%s\n" "${TARGET_APPS[@]}" "${CUSTOM_APPS[@]}" | awk '!seen[$0]++'))
fi
if $DO_INSTALL && [[ ${#TARGET_APPS[@]} -eq 0 ]]; then
  log "INFO: --install without --apps/--all. Using default app set."
  TARGET_APPS=("${DEFAULT_APPS[@]}")
fi

# -------- Actions --------
$DO_OPEN && open_mau_gui

if $DO_LIST; then
  log "Running 'msupdate --list'..."
  if "$MSUPDATE_BIN" --list | tee -a "$LOG_FILE"; then
    write_summary "Scan" "msupdate --list completed"
    log "List/scan completed."
  else
    write_summary "Error" "msupdate --list failed"
    log "ERROR: msupdate --list failed."
    if ! $DO_INSTALL; then exit 4; fi
  fi
fi

if $DO_INSTALL; then
  # Deferral UX
  load_state
  local apps_running=($(get_running_ms_apps))
  local list_text=""
  if [[ ${#apps_running[@]} -gt 0 ]]; then
    for a in "${apps_running[@]}"; do list_text+="- ${a}\n"; done
  else
    list_text="- (none detected)\n"
  fi

  # If deferrals below max, offer choice; else final prompt without deferral
  if [[ "$DEFERRALS" -lt "$MAX_DEFERRALS" ]]; then
    show_deferral_dialog "$list_text" "false"
    local choice=$?
    if [[ "$choice" -eq 0 ]]; then
      write_summary "User Choice" "Update Now (deferrals used: ${DEFERRALS}/${MAX_DEFERRALS})"
      # Attempt graceful quit and proceed
      [[ ${#apps_running[@]} -gt 0 ]] && quit_apps_gracefully "${apps_running[@]}"
    else
      DEFERRALS=$((DEFERRALS+1))
      save_state
      write_summary "User Choice" "Deferred (${DEFERRALS}/${MAX_DEFERRALS}); timer=${TIMER_SECONDS}s"
      log "User deferred. (${DEFERRALS}/${MAX_DEFERRALS})"
      exit 5
    fi
  else
    show_deferral_dialog "$list_text" "true"
    local final=$?
    if [[ "$final" -ne 0 ]]; then
      # If user closed the window unexpectedly, treat as proceed (final prompt enforces update)
      log "Final prompt closed; continuing with update."
    fi
    write_summary "User Choice" "Final prompt (no deferral)"
    [[ ${#apps_running[@]} -gt 0 ]] && quit_apps_gracefully "${apps_running[@]}"
  fi

  # Build app CSV
  APP_CSV=$(IFS=','; echo "${TARGET_APPS[*]}")
  log "Installing updates for: ${APP_CSV}"
  write_summary "Install Start" "Apps=${APP_CSV}"

  if "$MSUPDATE_BIN" --install --apps "$APP_CSV" --wait | tee -a "$LOG_FILE"; then
    write_summary "Install Complete" "Apps=${APP_CSV}"
    log "Install completed successfully."
  else
    log "ERROR: Install encountered errors. Retrying with --force..."
    write_summary "Install Retry" "Applying --force"
    if "$MSUPDATE_BIN" --install --apps "$APP_CSV" --wait --force | tee -a "$LOG_FILE"; then
      write_summary "Install Complete" "Second attempt succeeded"
      log "Second attempt completed."
    else
      write_summary "Error" "Install failed after retry"
      log "ERROR: Second attempt failed."
      exit 3
    fi
  fi
fi

write_summary "Script Complete" "mau_update.sh finished"
log "mau_update.sh completed."
exit 0
