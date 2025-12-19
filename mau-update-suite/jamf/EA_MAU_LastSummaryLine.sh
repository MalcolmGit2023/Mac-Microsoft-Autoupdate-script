#!/bin/bash
FILE="/Library/Logs/BHG/mau_update_summary.txt"
[[ -f "$FILE" ]] || { echo "<result>none</result>"; exit 0; }
LAST=$(tail -n 1 "$FILE")
echo "<result>${LAST}</result>"
