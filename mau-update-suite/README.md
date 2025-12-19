
# Microsoft AutoUpdate (MAU) Update Suite for macOS

This repository contains **three Bash scripts** designed for macOS fleets to manage Microsoft AutoUpdate (MAU) via Jamf Pro, plus **Extension Attributes** and **Smart Group guidance**. The suite is intentionally **unbranded** and suitable for general use.

## Contents

- `scripts/mau_update_basic.sh` – Minimal CLI workflow: open MAU (optional), scan/list, install.
- `scripts/mau_update_swiftdialog.sh` – User-friendly workflow with **SwiftDialog/Jamf Helper** prompts, deferral countdowns, graceful app close, human‑readable summaries.
- `scripts/mau_update_scan.sh` – Lightweight scanner for inventory: lists updates and exits; ideal for EA refresh jobs.
- `jamf/EA_MAU_PendingUpdates.sh` – Integer EA: counts pending Microsoft updates.
- `jamf/EA_MAU_Deferrals.sh` – Integer EA: reads local deferral count.
- `jamf/EA_MAU_LastSummaryLine.sh` – String EA: returns the last summary log line.
- `jamf/SmartGroup.md` – Steps to create Smart Groups in Jamf Pro.
- `LICENSE` – MIT License.

---

## Script Overviews

### 1) `mau_update_basic.sh`
**Purpose:** Jamf‑friendly baseline that uses the `msupdate` CLI to scan, list, and install Microsoft updates. Optional flag to open the MAU GUI. Robust logging and exit codes.

**Key features:**
- Detects `msupdate` in both common paths.
- `--list` (scan), `--install` (install) and `--open` (open MAU app).
- Defaults to a sensible set of Microsoft app IDs when none provided.
- Logs to `/var/log/mau_update.log`.

**Jamf usage:** Attach the script to a policy payload or run under Files & Processes as:
```
/usr/local/bin/mau_update_basic.sh --install --all
```

**Optional changes:**
- Trim the default app list (e.g., remove Teams/Edge if not managed via MAU).
- Change log path or verbosity.

---

### 2) `mau_update_swiftdialog.sh`
**Purpose:** End‑user friendly installer that prompts users to **save and close apps**, offers **deferral + countdown**, and writes **human‑readable summaries**. Falls back to Jamf Helper when SwiftDialog isn’t found.

**Key features:**
- Detects running Microsoft apps (Word, Excel, etc.).
- SwiftDialog prompt with **Update Now / Defer** buttons, **timer**, and **ESC to defer**.
- Configurable `--max-deferrals` and `--timer`.
- Graceful quits via AppleScript, run in the console user’s context.
- Summaries at `/Library/Logs/BHG/mau_update_summary.txt` and local state at `/Library/Application Support/BHG/MAU/state.txt`.

**Jamf usage:**
```
/usr/local/bin/mau_update_swiftdialog.sh --install --all --timer 300 --max-deferrals 3
```
Scope to Smart Groups based on pending updates or deferral count.

**Optional changes:**
- Replace icon path with a neutral icon.
- Add force‑close path (not recommended) after multiple failed attempts.
- Localize messages.

---

### 3) `mau_update_scan.sh`
**Purpose:** Lightweight scanner for scheduled inventory runs; prints `msupdate --list` output and exits with clear status. Good precursor for EA updates.

**Key features:**
- Fast path: detects `msupdate`, runs `--list`, writes to `/var/log/mau_update.log`.
- Exit codes suitable for reporting.

**Jamf usage:**
```
/usr/local/bin/mau_update_scan.sh
```
Trigger before EA refreshes to keep Smart Group data accurate.

**Optional changes:**
- Redirect output to a fleet log collector.
- Add JSON emission for SIEM ingestion.

---

## Extension Attributes (Jamf Pro)

- **MAU Pending Updates Count** (`EA_MAU_PendingUpdates.sh`): Integer. Counts distinct Microsoft app IDs reported by `msupdate --list`.
- **MAU Deferrals Count** (`EA_MAU_Deferrals.sh`): Integer. Reads `deferrals` from the local state file.
- **MAU Last Summary Line** (`EA_MAU_LastSummaryLine.sh`): String. Returns latest human‑readable summary line.

Import these as **Script EAs** in Jamf Pro.

---

## Smart Group Guidance
See `jamf/SmartGroup.md` for step‑by‑step criteria to create:
- **“Microsoft Updates Pending OR Deferrals Exceeded”** (Match Any): Pending > 0 OR Deferrals >= max.

---

## Installation & Permissions
- Place scripts in `/usr/local/bin/` and `chmod 755`.
- Ensure SwiftDialog is installed (or rely on Jamf Helper fallback).
- MAU (`msupdate`) must be present (bundled with Microsoft 365 PKGs). Mac App Store variants may use App Store updates.

---

## License
MIT. No branding included.
