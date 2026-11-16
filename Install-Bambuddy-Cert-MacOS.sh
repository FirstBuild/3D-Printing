#!/usr/bin/env bash
set -euo pipefail

CERT_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRINTERS_FILE="$SCRIPT_DIR/bambuddy-printers.json"
GITHUB_REPO="FirstBuild/3D-Printing"
GITHUB_BRANCH="main"

# Function to download the latest files from GitHub
download_latest_files() {
  # No temporary directory needed here; download directly to PRINTERS_FILE.
  echo "Downloading latest files from GitHub..."
  
  # Download bambuddy-printers.json
  if [[ -f "$PRINTERS_FILE" ]]; then
    local backup
    backup="$PRINTERS_FILE.bak.$(date +%Y%m%d-%H%M%S)"
    echo "Backing up existing printers file: $backup"
    cp "$PRINTERS_FILE" "$backup"
  fi
  
  if ! curl -fsSL -o "$PRINTERS_FILE" "https://raw.githubusercontent.com/$GITHUB_REPO/$GITHUB_BRANCH/bambuddy-printers.json"; then
    echo "Warning: Failed to download bambuddy-printers.json from GitHub"
    if [[ ! -f "$PRINTERS_FILE" ]]; then
      echo "Error: No local printers file and download failed"
      exit 1
    fi
  else
    echo "Successfully downloaded bambuddy-printers.json"
  fi
}

# Download latest files on startup
download_latest_files

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
  echo "Usage: $0 [--cert /path/to/custom-ca.crt] [--skip-printers]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert)
      CERT_FILE="${2:-}"
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
t = p.read_text()
t = t.replace("\r\n", "\n").strip()
if "-----BEGIN CERTIFICATE-----" not in t or "-----END CERTIFICATE-----" not in t:
    raise SystemExit("Certificate file does not look like PEM.")
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

TARGETS=()
TARGETS+=("/Applications/BambuStudio.app/Contents/Resources/cert/printer.cer")
TARGETS+=("/Applications/BambuStudioBeta.app/Contents/Resources/cert/printer.cer")
TARGETS+=("/Applications/OrcaSlicer.app/Contents/Resources/cert/printer.cer")

for target in "${TARGETS[@]}"; do
  append_cert_if_missing "$target"
done

configure_printers() {
  BAMBUDDY_PRINTERS_JSON="$BAMBUDDY_PRINTERS_JSON" python3 - <<'PY'
import base64
import concurrent.futures
import datetime
import getpass
import hashlib
import hmac
import json
import os
import pathlib
import pwd
import re
import shutil
import socket
import ssl
import struct
import subprocess
import time
import uuid

raw_printers = json.loads(os.environ["BAMBUDDY_PRINTERS_JSON"])
if not raw_printers:
    raise SystemExit(0)

staff_password = os.environ.get("BAMBUDDY_STAFF_PASSWORD", "")
staff_password_prompted = False

def get_staff_password():
    global staff_password, staff_password_prompted
    if staff_password:
        return staff_password
    if staff_password_prompted:
        return ""
    staff_password_prompted = True
    try:
        entered = getpass.getpass("Enter staff printer password (leave blank to skip staff-only printers): ")
    except Exception:
        entered = ""
    staff_password = entered.strip()
    return staff_password

def decrypt_access_code(encoded, password):
    parts = encoded.split(":")
    if len(parts) != 6 or parts[0] != "enc-v1":
        raise ValueError("unsupported encrypted access code format")

    iterations = int(parts[1])
    if iterations < 10000:
        raise ValueError("invalid KDF iteration count")

    salt = base64.b64decode(parts[2])
    nonce = base64.b64decode(parts[3])
    ciphertext = base64.b64decode(parts[4])
    expected_mac = base64.b64decode(parts[5])

    key_material = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations, dklen=64)
    enc_key = key_material[:32]
    mac_key = key_material[32:]

    actual_mac = hmac.new(mac_key, nonce + ciphertext, hashlib.sha256).digest()
    if not hmac.compare_digest(actual_mac, expected_mac):
        raise ValueError("wrong password or tampered encrypted access code")

    keystream = bytearray()
    counter = 0
    while len(keystream) < len(ciphertext):
        counter_bytes = counter.to_bytes(4, byteorder="big", signed=False)
        keystream.extend(hmac.new(enc_key, nonce + counter_bytes, hashlib.sha256).digest())
        counter += 1

    plaintext = bytes(c ^ k for c, k in zip(ciphertext, keystream))
    return plaintext.decode("utf-8")

printers = []
for printer in raw_printers:
    access_code = (printer.get("access_code") or "").strip()
    if not access_code and printer.get("encrypted_access_code"):
        password = get_staff_password()
        if not password:
            print(f"Skipping staff printer '{printer.get('name', 'unknown')}' because no staff password was supplied.")
            continue
        try:
            access_code = decrypt_access_code(printer["encrypted_access_code"], password)
        except Exception as ex:
            print(f"Skipping staff printer '{printer.get('name', 'unknown')}': {ex}")
            continue

    if not access_code:
        print(f"Skipping printer '{printer.get('name', 'unknown')}' because it does not contain a usable access code.")
        continue

    next_printer = dict(printer)
    next_printer["access_code"] = access_code
    printers.append(next_printer)

if not printers:
    raise SystemExit(0)

def user_home():
    sudo_user = os.environ.get("SUDO_USER")
    if sudo_user and sudo_user != "root":
        return pathlib.Path(pwd.getpwnam(sudo_user).pw_dir)
    return pathlib.Path.home()

home = user_home()
configs = [
    {
        "path": home / "Library" / "Application Support" / "BambuStudio" / "BambuStudio.conf",
        "markers": [pathlib.Path("/Applications/BambuStudio.app")],
    },
    {
        "path": home / "Library" / "Application Support" / "BambuStudioBeta" / "BambuStudio.conf",
        "markers": [pathlib.Path("/Applications/BambuStudioBeta.app")],
    },
    {
        "path": home / "Library" / "Application Support" / "OrcaSlicer" / "OrcaSlicer.conf",
        "markers": [pathlib.Path("/Applications/OrcaSlicer.app")],
    },
]

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

def is_ipv4(value):
    if not value:
        return False
    parts = value.split(".")
    return len(parts) == 4 and all(p.isdigit() and 0 <= int(p) <= 255 for p in parts)

def resolve_host_to_ipv4(hostname):
    if not hostname:
        return None
    if is_ipv4(hostname):
        return hostname
    try:
        ip = socket.gethostbyname(hostname)
        if is_ipv4(ip):
            return ip
    except OSError:
        pass
    return None

def get_local_ipv4_subnets():
    prefixes = set()
    # Check default route local IP via UDP socket (no packets sent)
    for target in ("192.168.68.1", "8.8.8.8"):
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
                s.connect((target, 80))
                ip = s.getsockname()[0]
                if is_ipv4(ip) and not ip.startswith(("127.", "169.254.")):
                    prefixes.add(".".join(ip.split(".")[:3]))
        except OSError:
            pass
    # Also inspect interface addresses via ifconfig / ip
    for cmd in (["ifconfig"], ["ip", "-4", "addr"]):
        try:
            out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True)
            for match in re.findall(r"\binet\s+(\d+\.\d+\.\d+\.\d+)", out):
                if is_ipv4(match) and not match.startswith(("127.", "169.254.")):
                    prefixes.add(".".join(match.split(".")[:3]))
        except (OSError, subprocess.SubprocessError):
            pass
    return sorted(prefixes)

def probe_tls_serial(ip, target_serials):
    try:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        with socket.create_connection((ip, 8883), timeout=0.45) as sock:
            with ctx.wrap_socket(sock, server_hostname=ip) as ssock:
                der = ssock.getpeercert(binary_form=True)
                if not der:
                    return None
                for serial in target_serials:
                    if serial.encode("ascii") in der:
                        return (serial, ip)
    except OSError:
        pass
    return None

def discover_printers(serials):
    discovered = {}
    target_set = {s for s in serials if s}
    if not target_set:
        return discovered

    print("Discovering printers on the local network...")

    # 1. Passive Bambu SSDP discovery on UDP port 2021
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP) as udp:
            udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            if hasattr(socket, "SO_REUSEPORT"):
                try:
                    udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                except OSError:
                    pass
            udp.bind(("", 2021))
            udp.settimeout(0.25)
            try:
                mreq = struct.pack("4sl", socket.inet_aton("239.255.255.250"), socket.INADDR_ANY)
                udp.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
            except OSError:
                pass

            deadline = time.monotonic() + 2.5
            while time.monotonic() < deadline and len(discovered) < len(target_set):
                try:
                    data, addr = udp.recvfrom(4096)
                except socket.timeout:
                    continue
                text = data.decode("utf-8", errors="ignore")
                usn_match = re.search(r"(?im)^USN:\s*([^\r\n]+)", text)
                loc_match = re.search(r"(?im)^Location:\s*([^\r\n]+)", text)
                usn = usn_match.group(1).strip() if usn_match else None
                loc = loc_match.group(1).strip() if loc_match else None
                if usn in target_set and usn not in discovered:
                    ip_candidate = None
                    if loc and is_ipv4(loc):
                        ip_candidate = loc
                    elif loc:
                        m = re.search(r"(\d{1,3}(?:\.\d{1,3}){3})", loc)
                        if m and is_ipv4(m.group(1)):
                            ip_candidate = m.group(1)
                    if not ip_candidate and addr and is_ipv4(addr[0]):
                        ip_candidate = addr[0]
                    if ip_candidate:
                        discovered[usn] = ip_candidate
                        print(f"  Discovered (SSDP): {usn} -> {ip_candidate}")
    except OSError:
        pass

    # 2. Active subnet scan on TCP port 8883 + TLS cert check for remaining printers
    remaining = target_set - set(discovered.keys())
    if remaining:
        subnets = get_local_ipv4_subnets()
        candidates = [f"{prefix}.{i}" for prefix in subnets for i in range(1, 255)]
        if candidates:
            with concurrent.futures.ThreadPoolExecutor(max_workers=64) as executor:
                futures = [executor.submit(probe_tls_serial, ip, remaining) for ip in candidates]
                for fut in concurrent.futures.as_completed(futures):
                    res = fut.result()
                    if res:
                        serial, ip = res
                        if serial not in discovered:
                            discovered[serial] = ip
                            print(f"  Discovered (TLS 8883): {serial} -> {ip}")

    return discovered

def get_connect_host(printer, discovered_hosts):
    serial = printer.get("serial")
    if serial and serial in discovered_hosts:
        return discovered_hosts[serial]

    host = (printer.get("host") or "").strip()
    if host:
        resolved = resolve_host_to_ipv4(host)
        return resolved if resolved else host

    alternate_hosts = printer.get("alternate_hosts") or []
    for alt in alternate_hosts:
        if not is_ipv4(alt):
            resolved = resolve_host_to_ipv4(alt)
            if resolved:
                return resolved
    for alt in alternate_hosts:
        if is_ipv4(alt):
            return alt
    return alternate_hosts[0] if alternate_hosts else None

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
    # Some slicer config files append metadata lines like '# MD5: ...' after the JSON body.
    text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    return json.loads(text)

def patch_config(path, discovered_hosts):
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
        connect_host = get_connect_host(printer, discovered_hosts)
        config["access_code"][serial] = printer["access_code"]
        config["user_access_code"][serial] = printer["access_code"]
        if connect_host:
            config["ip_address"][serial] = connect_host
            config["user_access_dev_ip"][serial] = encode_dev_ip(connect_host, slicer_uuid)
        else:
            print(f"Warning: Could not discover IP for '{printer.get('name', serial)}' ({serial}). Skipping IP configuration for this printer.")

    if path.exists():
        backup = path.with_name(path.name + ".bak." + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
        shutil.copy2(path, backup)
        print(f"Config backup created: {backup}")

    path.write_text(json.dumps(config, indent=4, ensure_ascii=False) + "\n")
    print(f"Configured Bambuddy printers in: {path}")

discovered_hosts = discover_printers([p.get("serial") for p in printers])

for entry in configs:
    if should_patch(entry):
        patch_config(entry["path"], discovered_hosts)
PY
}

configure_printers

echo ""
echo "Done. Fully quit and restart Bambu Studio / Bambu Studio Beta / OrcaSlicer with Cmd+Q."
