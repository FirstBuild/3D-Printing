#!/usr/bin/env bash
set -euo pipefail

CERT_FILE=""
APPIMAGE_ROOT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINTERS_FILE="$SCRIPT_DIR/bambuddy-printers.json"
[[ -f "$PRINTERS_FILE" ]] || { echo "Printer definition file not found: $PRINTERS_FILE"; exit 1; }
BAMBUDDY_PRINTERS_JSON="$(cat "$PRINTERS_FILE")"
EMBEDDED_CERT_TEXT="$(cat <<'EOF'
-----BEGIN CERTIFICATE-----
MIIC7jCCAdagAwIBAgIUUmyk3xDkK7Y+H0YULvJNkM0tZ0YwDQYJKoZIhvcNAQEL
BQAwHTEbMBkGA1UEAwwSVmlydHVhbCBQcmludGVyIENBMB4XDTI2MDUwNzE0MTAw
NloXDTQ2MDUwMjE0MTAwNlowHTEbMBkGA1UEAwwSVmlydHVhbCBQcmludGVyIENB
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxkHmyXYLpSCuSvlnQigN
kmFMcfYp+RZRpC3OFYpXykpI9j3KScVzP19S4cuz2oMM+lWH09215sCOPrEbX4fa
XFgMnrNfhY3oWXbyxNXZ5xqPeDu6hS3hXuayKxaFMKJ1i1a9+NlRJRgHOQfBVeON
BXjvhv2ar4BxYXvm0AfLFqh9dRvQEWz3s32incyKn1CvfCjPuU2WfimPEh8oAZwP
wWf6sjVpdcV3GEKid06LubKDECRiA/2sLTP2Y13H2ASZ5aT05M/HAhGvGFNgGmfR
JM8WeyfnWN88/CfEWZcn13QCS4bFiLLFbtfieHSe5NFs3y345sJM825SPeQWhJ3O
HQIDAQABoyYwJDASBgNVHRMBAf8ECDAGAQH/AgEAMA4GA1UdDwEB/wQEAwIBhjAN
BgkqhkiG9w0BAQsFAAOCAQEAYixtxZwX3IX7UuCi6QRiHiMKIsz/lgppLPOlmwce
atUKj3/gxYsIK1y1HzlFvMnh9CKA6O/+TqgRYZ/2Jbvxe+p77l4sUtk9ZkK0AOTv
BBHiNuItJwxHVYlccM9/umOC7pe2z1H0vTAIUsiSIX3mo7C4oOcj9gb9zhSxk7mL
NWzfsPQL+mH9OdNssSAviT90XKymQ0T0W9za0h4mIakTuhW97RriVIng0y6gFGzD
fIWR5OekM5U9z60uXx9YoEdWhp2rQxay+a0GYc+MG5kNuK2P32ho/o2/o8RlzWys
r7K/uMmuVh0cxZctYp29J4BwPlB0wdc5ns8W+vvpUYID+Q==
-----END CERTIFICATE-----
EOF
)"
CERT_TEXT="$EMBEDDED_CERT_TEXT"

usage() {
  cat <<'EOF'
Usage:
  install-bambuddy-cert-linux.sh [options]

Options:
  --appimage-root PATH       Path to extracted AppImage squashfs-root
  --cert PATH                Override embedded Bambuddy CA certificate file
  --skip-printers            Install the certificate only

Examples:
  sudo ./install-bambuddy-cert-linux.sh

  sudo ./install-bambuddy-cert-linux.sh --cert ./custom-ca.crt

  ./install-bambuddy-cert-linux.sh --appimage-root ./squashfs-root
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert)
      CERT_FILE="${2:-}"
      shift 2
      ;;
    --appimage-root)
      APPIMAGE_ROOT="${2:-}"
      shift 2
      ;;
    --skip-printers)
      BAMBUDDY_PRINTERS_JSON="[]"
      shift
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -n "$CERT_FILE" ]]; then
  [[ -f "$CERT_FILE" ]] || { echo "Certificate file not found: $CERT_FILE"; exit 1; }
  CERT_TEXT="$(python3 - "$CERT_FILE" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text().replace("\r\n", "\n").strip()
if "-----BEGIN CERTIFICATE-----" not in t or "-----END CERTIFICATE-----" not in t:
    raise SystemExit(f"Certificate file does not look like PEM: {p}")
print(t)
PY
)"
fi

BAMBUDDY_CERT_TEXT="$CERT_TEXT" python3 - <<'PY'
import os
t = os.environ["BAMBUDDY_CERT_TEXT"].replace("\r\n", "\n").strip()
if "-----BEGIN CERTIFICATE-----" not in t or "-----END CERTIFICATE-----" not in t:
    raise SystemExit("Embedded certificate does not look like PEM.")
PY

append_cert_if_missing() {
  local target="$1"

  if [[ ! -f "$target" ]]; then
    return
  fi

  BAMBUDDY_CERT_TEXT="$CERT_TEXT" python3 - "$target" <<'PY'
import os, sys, pathlib, shutil, datetime

target = pathlib.Path(sys.argv[1])

target_text = target.read_text()
cert_text = os.environ["BAMBUDDY_CERT_TEXT"].replace("\r\n", "\n").strip()

if "-----BEGIN CERTIFICATE-----" not in cert_text or "-----END CERTIFICATE-----" not in cert_text:
    raise SystemExit("Certificate does not look like PEM.")

normalized_target = target_text.replace("\r\n", "\n")

if cert_text in normalized_target:
    print(f"Already installed: {target}")
    raise SystemExit(0)

backup = target.with_name(target.name + ".bak." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
shutil.copy2(target, backup)
print(f"Backup created: {backup}")

with target.open("a", newline="\n") as f:
    if not target_text.endswith("\n"):
        f.write("\n")
    f.write("\n")
    f.write(cert_text)
    f.write("\n")

print(f"Installed Bambuddy CA into: {target}")
PY
}

install_direct() {
  local targets=()

  if [[ -n "$APPIMAGE_ROOT" ]]; then
    targets+=("$APPIMAGE_ROOT/usr/share/Bambu Studio/resources/cert/printer.cer")
    targets+=("$APPIMAGE_ROOT/usr/share/BambuStudioBeta/resources/cert/printer.cer")
    targets+=("$APPIMAGE_ROOT/usr/share/Bambu Studio Beta/resources/cert/printer.cer")
    targets+=("$APPIMAGE_ROOT/usr/share/OrcaSlicer/resources/cert/printer.cer")
  else
    targets+=("/usr/share/Bambu Studio/resources/cert/printer.cer")
    targets+=("/usr/share/BambuStudioBeta/resources/cert/printer.cer")
    targets+=("/usr/share/Bambu Studio Beta/resources/cert/printer.cer")
    targets+=("/usr/share/OrcaSlicer/resources/cert/printer.cer")
  fi

  for target in "${targets[@]}"; do
    append_cert_if_missing "$target"
  done
}

configure_printers() {
  BAMBUDDY_PRINTERS_JSON="$BAMBUDDY_PRINTERS_JSON" BAMBUDDY_APPIMAGE_ROOT="$APPIMAGE_ROOT" python3 - <<'PY'
import datetime
import json
import os
import pathlib
import pwd
import shutil
import uuid

printers = json.loads(os.environ["BAMBUDDY_PRINTERS_JSON"])
if not printers:
    raise SystemExit(0)

def user_home():
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root":
        return pathlib.Path(pwd.getpwnam(sudo_user).pw_dir)
    return pathlib.Path.home()

home = user_home()
appimage_root = os.environ.get("BAMBUDDY_APPIMAGE_ROOT")
configs = [
    {
        "path": home / ".config" / "BambuStudio" / "BambuStudio.conf",
        "markers": [pathlib.Path("/usr/share/Bambu Studio")],
    },
    {
        "path": home / ".config" / "BambuStudioBeta" / "BambuStudio.conf",
        "markers": [
            pathlib.Path("/usr/share/BambuStudioBeta"),
            pathlib.Path("/usr/share/Bambu Studio Beta"),
        ],
    },
    {
        "path": home / ".config" / "OrcaSlicer" / "OrcaSlicer.conf",
        "markers": [pathlib.Path("/usr/share/OrcaSlicer")],
    },
]

if appimage_root:
    root = pathlib.Path(appimage_root)
    configs[0]["markers"].append(root / "usr/share/Bambu Studio")
    configs[1]["markers"].extend([
        root / "usr/share/BambuStudioBeta",
        root / "usr/share/Bambu Studio Beta",
    ])
    configs[2]["markers"].append(root / "usr/share/OrcaSlicer")

def should_patch(entry):
    path = entry["path"]
    return path.exists() or any(marker.exists() for marker in entry["markers"])

class Mt19937:
    def __init__(self, seed):
        self.mt = [0] * 624
        self.index = 624
        self.mt[0] = seed & 0xFFFFFFFF
        for i in range(1, 624):
            self.mt[i] = (1812433253 * (self.mt[i - 1] ^ (self.mt[i - 1] >> 30)) + i) & 0xFFFFFFFF

    def twist(self):
        for i in range(624):
            y = (self.mt[i] & 0x80000000) + (self.mt[(i + 1) % 624] & 0x7FFFFFFF)
            self.mt[i] = self.mt[(i + 397) % 624] ^ (y >> 1)
            if y & 1:
                self.mt[i] ^= 0x9908B0DF
            self.mt[i] &= 0xFFFFFFFF
        self.index = 0

    def rand(self):
        if self.index >= 624:
            self.twist()
        y = self.mt[self.index]
        self.index += 1
        y ^= y >> 11
        y ^= (y << 7) & 0x9D2C5680
        y ^= (y << 15) & 0xEFC60000
        y ^= y >> 18
        return y & 0xFFFFFFFF

def encode_dev_ip(host, slicer_uuid):
    if not host or not slicer_uuid:
        return host
    seed = 2166136261
    for ch in slicer_uuid.encode("utf-8"):
        seed ^= ch
        seed = (seed * 16777619) & 0xFFFFFFFF
    rng = Mt19937(seed)
    return bytes((b ^ (rng.rand() & 0xFF)) for b in host.encode("utf-8")).hex()

def get_connect_host(printer):
    host = printer["host"]
    if all(part.isdigit() and 0 <= int(part) <= 255 for part in host.split(".")) and host.count(".") == 3:
        return host
    alternate_hosts = printer.get("alternate_hosts") or []
    return alternate_hosts[0] if alternate_hosts else host

def ensure_slicer_uuid(config):
    app_config = config.get("app")
    if app_config is None:
        app_config = {}
        config["app"] = app_config
    elif not isinstance(app_config, dict):
        raise SystemExit("Config key is not an object: app")

    slicer_uuid = app_config.get("slicer_uuid") or config.get("slicer_uuid")
    if not slicer_uuid:
        slicer_uuid = str(uuid.uuid4())
    app_config["slicer_uuid"] = slicer_uuid
    return slicer_uuid

def load_config(path):
    if not path.exists():
        return {}
    text = path.read_text()
    if not text.strip():
        return {}
    return json.loads(text)

def patch_config(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    config = load_config(path)
    if not isinstance(config, dict):
        raise SystemExit(f"Config root is not an object: {path}")

    slicer_uuid = ensure_slicer_uuid(config)

    for key in ("access_code", "user_access_code", "ip_address", "user_access_dev_ip"):
        current = config.get(key)
        if current is None:
            config[key] = {}
        elif not isinstance(current, dict):
            raise SystemExit(f"Config key is not an object: {path}: {key}")

    for printer in printers:
        serial = printer["serial"]
        connect_host = get_connect_host(printer)
        config["access_code"][serial] = printer["access_code"]
        config["user_access_code"][serial] = printer["access_code"]
        config["ip_address"][serial] = connect_host
        config["user_access_dev_ip"][serial] = encode_dev_ip(connect_host, slicer_uuid)

    if path.exists():
        backup = path.with_name(path.name + ".bak." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, backup)
        print(f"Config backup created: {backup}")

    path.write_text(json.dumps(config, indent=4, ensure_ascii=False) + "\n")
    print(f"Configured Bambuddy printers in: {path}")

for entry in configs:
    if should_patch(entry):
        patch_config(entry["path"])
PY
}

install_direct
configure_printers

echo ""
echo "Done. Fully quit and restart Bambu Studio / Bambu Studio Beta / OrcaSlicer."
