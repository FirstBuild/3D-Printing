# 3D Printing @ FirstBuild
The purpose of this repository is to store information about using 3D printing resources in the Louisville, KY FirstBuild Makerspace.

## Installing Bambu Certificate

These scripts install the certificate required to connect to the Bambu Lab printers in the FirstBuild makerspace.

### Quick Install

Choose the instructions for your operating system:

#### macOS

Run this command in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/FirstBuild/3D-Printing/main/Install-Bambuddy-Cert-MacOS.sh | bash
```

The script will automatically download the latest certificate and printer configuration files from GitHub.

#### Linux

Run this command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/FirstBuild/3D-Printing/main/Install-Bambuddy-Cert-Linux.sh | bash
```

The script will automatically download the latest certificate and printer configuration files from GitHub.

#### Windows

> **Important:** Download the full repository as a ZIP file. The scripts need access to local files to function properly.

**Download and Setup:**

1. Go to `https://github.com/FirstBuild/3D-Printing`
2. Click the green **Code** button and select **Download ZIP**
3. Extract the ZIP file to a location like `C:\Users\YourUsername\Downloads\3D-Printing-main`

**Option 1: Using Batch File (Easiest)**

1. Navigate to the extracted folder
2. Double-click `Install-BambuddyCert.bat` to run it
   - The script will automatically download the latest configuration files
   - Command Prompt will open, run the script, and close when complete

**Option 2: Using PowerShell**

1. Right-click on `Install-BambuddyCert.ps1` and select **Run with PowerShell**
   - If this option doesn't appear, use the manual method below
2. The script will automatically download the latest configuration files

**Manual PowerShell Method:**

1. Open PowerShell **as Administrator**
2. Navigate to the extracted folder:
   ```powershell
   cd C:\Users\YourUsername\Downloads\3D-Printing-main
   ```
3. Run these commands:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
   .\Install-BambuddyCert.ps1
   ```

---

## Adding Printers to Bambu Studio
Once the script has been ran, re-open Bambu Studio and make sure you're connected to the `Firstbuild_private` WiFi network. The printers should automatically show up in Bambu Studio after a few minutes.

## Staff-Only Printer Access Codes

Public printers can keep using plain `access_code` values. Staff-only printers can use encrypted codes instead.

### JSON format

For staff printers, set:

- `staff_only: true`
- `encrypted_access_code: "enc-v1:..."`

The installer scripts support both formats:

- Public: `access_code`
- Staff: `encrypted_access_code`

If an encrypted staff code is present, the installer prompts once for a staff password.
If no password is entered, staff-only printers are skipped and public printers are still configured.

### Easy update workflow for staff codes

1. In `bambuddy-printers.json`, set `staff_only: true` on staff printers.
2. Update each staff printer's plain `access_code` to the new value.
3. Run:

```bash
python3 Protect-Staff-AccessCodes.py --file bambuddy-printers.json
```

4. Enter the staff encryption password when prompted.
5. The script replaces plain staff `access_code` values with `encrypted_access_code`.

Tip: use the same staff password expected by team members who run installer scripts.
