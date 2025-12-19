#!/bin/bash
MSU="/Applications/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
[[ -x "$MSU" ]] || MSU="/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"
[[ -x "$MSU" ]] || { echo "<result>0</result>"; exit 0; }
OUT="$($MSU --list 2>/dev/null)"
COUNT=$(echo "$OUT" | grep -Eo 'com\.microsoft\.[A-Za-z0-9\.\-]+' | sort -u | wc -l | tr -d ' ')
[[ -z "$COUNT" ]] && COUNT=0
echo "<result>${COUNT}</result>"
