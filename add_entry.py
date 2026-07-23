#!/usr/bin/env python3

import subprocess
import sys
import os
import string
import secrets
from getpass import getpass

VAULT_FILE = "/dev/shm/passwords.yaml"


def generate_password(length=25, exclude_chars=""):
    chars = "".join(
        c
        for c in string.ascii_letters + string.digits + string.punctuation
        if c not in exclude_chars
    )

    return "".join(secrets.choice(chars) for _ in range(length))


def yaml_escape(value):
    value = str(value)

    value = value.replace("\\", "\\\\")
    value = value.replace('"', '\\"')
    value = value.replace("\n", "\\n")

    return f'"{value}"'


def unquote(value):

    if value.startswith('"') and value.endswith('"'):
        value = value[1:-1]
        value = value.replace("\\n", "\n")
        value = value.replace('\\"', '"')
        value = value.replace("\\\\", "\\")

    return value


def load_vault(filename):

    entries = []

    if not os.path.exists(filename):
        return entries

    current = None

    with open(filename, "r", encoding="utf-8") as f:

        for line in f:

            line = line.rstrip()

            if line.startswith("  - "):

                if current:
                    entries.append(current)

                current = {}

                key, value = line[4:].split(":", 1)
                current[key.strip()] = unquote(value.strip())

            elif line.startswith("    ") and current:

                key, value = line.strip().split(":", 1)
                current[key] = unquote(value.strip())

    if current:
        entries.append(current)

    return entries


def save_vault(filename, entries):

    with open(filename, "w", encoding="utf-8") as f:

        f.write("entries:\n")

        for entry in entries:

            f.write(f"  - id: {yaml_escape(entry['id'])}\n")

            for field in [
                "title",
                "username",
                "password",
                "notes",
                "url",
                "totp",
            ]:

                if field in entry and entry[field]:
                    f.write(f"    {field}: {yaml_escape(entry[field])}\n")

            f.write("\n")


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

    entries = load_vault(VAULT_FILE)

    entries.append(add_entry(entries))

    save_vault(VAULT_FILE, entries)

    run_sort_script()

    print("Entry added and vault sorted.")
