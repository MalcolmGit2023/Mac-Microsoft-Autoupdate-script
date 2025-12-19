#!/bin/bash
STATE_FILE="/Library/Application Support/MAU/state.txt"
COUNT=$(awk -F= '/^deferrals=/{print $2}' "$STATE_FILE" 2>/dev/null)
[[ -z "$COUNT" ]] && COUNT=0
echo "<result>${COUNT}</result>"
