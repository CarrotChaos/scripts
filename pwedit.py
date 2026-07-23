#!/usr/bin/env python3

import sys
import os
import subprocess
import string
import secrets
from getpass import getpass
from vault_lib import load_vault, save_vault

VAULT_FILE = "/dev/shm/passwords.json"


def generate_password(length=25, exclude_chars=""):

    chars = "".join(
        c
        for c in string.ascii_letters + string.digits + string.punctuation
        if c not in exclude_chars
    )
    return "".join(secrets.choice(chars) for _ in range(length))


def run_sort():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sort_script = os.path.join(script_dir, "sort_vault.py")
    subprocess.run([sys.executable, sort_script, VAULT_FILE, VAULT_FILE], check=True)


def find_entry(entries, entry_id):
    return next(
        (entry for entry in entries if entry.get("id") == entry_id),
        None,
    )


def main():
    if len(sys.argv) != 2:
        print("Usage:\n" "  python3 pwedit.py ENTRY_ID")
        sys.exit(1)
    entry_id = sys.argv[1]
    entries = load_vault()
    entry = find_entry(entries, entry_id)
    if not entry:
        print("Entry not found")
        sys.exit(1)
    print()
    print("Title:", entry.get("title", ""))
    print("Username:", entry.get("username", ""))
    print()

    choice = input("Generate password? [Y/n]: ").strip().lower()
    if choice in ("", "y", "yes"):
        length_input = input("Password length (default 25): ").strip()
        length = int(length_input) if length_input else 25
        exclude = input("Characters to exclude (optional): ")
        new_password = generate_password(length, exclude)
        print()
        print("Generated password:")
        print(new_password)
        print()

        confirm = input("Use this password? [Y/n]: ").strip().lower()
        if confirm not in ("", "y", "yes"):
            print("Cancelled")
            sys.exit(0)

    else:
        new_password = getpass("New password: ")
        confirm_password = getpass("Confirm password: ")
        if new_password != confirm_password:
            print("Passwords do not match")
            sys.exit(1)

    confirm = input("\nReplace existing password? [y/N]: ").strip().lower()
    if confirm not in ("y", "yes"):
        print("Cancelled")
        sys.exit(0)

    entry["password"] = new_password

    save_vault(entries)

    run_sort()

    print("Password updated.")


if __name__ == "__main__":
    main()
