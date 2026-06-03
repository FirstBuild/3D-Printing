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

The script will automatically download the latest printer configuration file from GitHub.

#### Linux

Run this command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/FirstBuild/3D-Printing/main/Install-Bambuddy-Cert-Linux.sh | bash
```

The script will automatically download the latest printer configuration file from GitHub.

#### Windows

**Three steps — no ZIP download needed:**

1. Go to `https://github.com/FirstBuild/3D-Printing` and click on **`Install-BambuddyCert.bat`**
2. Click the **download** button (the icon with a downward arrow, near the top-right of the file view) and save the file anywhere — your Desktop works great
3. Double-click the downloaded `Install-BambuddyCert.bat` file

A black Command Prompt window will open, download everything it needs from the internet, install the certificate, and configure the printers automatically. When it says **"Done!"**, press any key to close it.

> **Tip:** If Windows asks "Do you want to allow this app to make changes?", click **Yes**. If you see a blue SmartScreen warning, click **More info** then **Run anyway**.

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
