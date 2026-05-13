#!/usr/bin/env bash
set -euo pipefail

CERT_FILE=""
APPIMAGE_ROOT=""
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
    targets+=("$APPIMAGE_ROOT/usr/share/OrcaSlicer/resources/cert/printer.cer")
  else
    targets+=("/usr/share/Bambu Studio/resources/cert/printer.cer")
    targets+=("/usr/share/OrcaSlicer/resources/cert/printer.cer")
  fi

  for target in "${targets[@]}"; do
    append_cert_if_missing "$target"
  done
}

install_direct

echo ""
echo "Done. Fully quit and restart Bambu Studio / OrcaSlicer."
