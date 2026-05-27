#!/usr/bin/env python3
"""Encrypt staff printer access codes in bambuddy-printers.json.

Workflow:
1) Mark staff printers with "staff_only": true
2) Set/update their plain "access_code"
3) Run this script to replace plain staff codes with "encrypted_access_code"
"""

from __future__ import annotations

import argparse
import base64
import getpass
import hashlib
import hmac
import json
import secrets
from pathlib import Path

ITERATIONS = 200_000
FORMAT_PREFIX = "enc-v1"


def encrypt_access_code(access_code: str, password: str, iterations: int = ITERATIONS) -> str:
    salt = secrets.token_bytes(16)
    nonce = secrets.token_bytes(16)
    key_material = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations, dklen=64)
    enc_key = key_material[:32]
    mac_key = key_material[32:]

    plaintext = access_code.encode("utf-8")
    keystream = bytearray()
    counter = 0
    while len(keystream) < len(plaintext):
        counter_bytes = counter.to_bytes(4, byteorder="big", signed=False)
        keystream.extend(hmac.new(enc_key, nonce + counter_bytes, hashlib.sha256).digest())
        counter += 1

    ciphertext = bytes(p ^ k for p, k in zip(plaintext, keystream))
    mac = hmac.new(mac_key, nonce + ciphertext, hashlib.sha256).digest()

    return ":".join(
        [
            FORMAT_PREFIX,
            str(iterations),
            base64.b64encode(salt).decode("ascii"),
            base64.b64encode(nonce).decode("ascii"),
            base64.b64encode(ciphertext).decode("ascii"),
            base64.b64encode(mac).decode("ascii"),
        ]
    )


def prompt_password() -> str:
    first = getpass.getpass("Enter staff encryption password: ").strip()
    if not first:
        raise SystemExit("Password cannot be empty.")
    second = getpass.getpass("Re-enter staff encryption password: ").strip()
    if first != second:
        raise SystemExit("Passwords do not match.")
    return first


def process_file(path: Path, password: str, rotate_all: bool) -> tuple[int, int]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise SystemExit("Expected top-level JSON array.")

    encrypted_count = 0
    skipped_count = 0

    for printer in data:
        if not isinstance(printer, dict):
            skipped_count += 1
            continue

        if not bool(printer.get("staff_only")):
            continue

        plain_code = (printer.get("access_code") or "").strip()
        encrypted_code = (printer.get("encrypted_access_code") or "").strip()

        if plain_code:
            printer["encrypted_access_code"] = encrypt_access_code(plain_code, password)
            printer.pop("access_code", None)
            encrypted_count += 1
            continue

        if rotate_all and encrypted_code:
            raise SystemExit(
                "--rotate-all requires plain access_code values for staff printers. "
                "Set access_code temporarily, then rerun."
            )

        if not encrypted_code:
            skipped_count += 1

    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return encrypted_count, skipped_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Encrypt staff-only printer access codes.")
    parser.add_argument(
        "--file",
        default="bambuddy-printers.json",
        help="Path to printers JSON file (default: bambuddy-printers.json)",
    )
    parser.add_argument(
        "--password",
        default="",
        help="Staff encryption password (omit to be prompted securely)",
    )
    parser.add_argument(
        "--rotate-all",
        action="store_true",
        help="Validate that all staff entries are provided as plain access_code for full re-encryption",
    )

    args = parser.parse_args()
    target = Path(args.file)
    if not target.exists():
        raise SystemExit(f"File not found: {target}")

    password = args.password.strip() or prompt_password()
    encrypted_count, skipped_count = process_file(target, password, args.rotate_all)

    print(f"Updated {encrypted_count} staff printer access code(s).")
    if skipped_count:
        print(f"Skipped {skipped_count} staff entry/entries with no access code fields.")


if __name__ == "__main__":
    main()
