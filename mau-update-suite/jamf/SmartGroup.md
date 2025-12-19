
# Jamf Pro Smart Group: Microsoft Updates Pending OR Deferrals Exceeded

Create a **Smart Computer Group** with **Match any** of the following:

1. **MAU Pending Updates Count** is **greater than** `0`
2. **MAU Deferrals Count** is **greater than or equal to** `3` *(align to your `--max-deferrals`)*

Optional additional criteria:
- Operating System **like** `macOS`
- Computer Group **is** `macOS Fleet`

Use this group to scope the **Install** policy (e.g., `mau_update_swiftdialog.sh`).
