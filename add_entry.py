#!/usr/bin/env python3

import subprocess
import sys
import os
import string
import secrets
from getpass import getpass
from vault_lib import load_vault, save_vault

VAULT_FILE = "/dev/shm/passwords.yaml"


def generate_password(length=25, exclude_chars=""):
    chars = "".join(
        c
        for c in string.ascii_letters + string.digits + string.punctuation
        if c not in exclude_chars
    )

    return "".join(secrets.choice(chars) for _ in range(length))


def run_sort_script():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sort_script = os.path.join(script_dir, "sort_vault.py")

    subprocess.run([sys.executable, sort_script, VAULT_FILE, VAULT_FILE], check=True)


def add_entry(entries):

    print("\n--- Add New Password Entry ---\n")

    entry = {}

    entry["id"] = generate_id(entries)

    entry["title"] = input("Title: ").strip()
    entry["username"] = input("Username: ").strip()

    password = getpass("Password (leave blank to generate): ")

    if not password:

        length_input = input("Password length (default 25): ").strip()

        length = int(length_input) if length_input else 25

        exclude_chars = input("Characters to exclude (optional): ")

        password = generate_password(length, exclude_chars)

        print("\nGenerated password:")
        print(password)
        print()

    entry["password"] = password

    notes = input("Notes (optional): ").strip()
    url = input("URL (optional): ").strip()
    totp = input("TOTP (optional): ").strip()

    if notes:
        entry["notes"] = notes

    if url:
        entry["url"] = url

    if totp:
        entry["totp"] = totp

    return entry


def generate_id(entries):

    existing = {entry.get("id", "") for entry in entries}

    while True:

        new_id = secrets.token_hex(6)

        if new_id not in existing:
            return new_id


if __name__ == "__main__":
    entries = load_vault()
    entries.append(add_entry(entries))
    save_vault(entries)
    run_sort_script()
    print("Entry added and vault sorted.")
