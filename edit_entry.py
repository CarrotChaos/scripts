#!/usr/bin/env python3

import os
import tempfile
import subprocess

from vault_lib import load_vault, save_vault

EDITOR = [
    "nvim",
    "-i",
    "NONE",
    "-n",
    "-c",
    "set noswapfile nobackup nowritebackup noundofile shada= clipboard=",
]


def find_entry(entries, entry_id):

    for entry in entries:
        if entry.get("id") == entry_id:
            return entry

    return None


def entry_to_text(entry):

    lines = []

    lines.append(f"Title: {entry.get('title', '')}")
    lines.append(f"Username: {entry.get('username', '')}")
    lines.append(f"Password: {entry.get('password', '')}")

    if entry.get("url"):
        lines.append(f"URL: {entry['url']}")

    if entry.get("totp"):
        lines.append(f"TOTP: {entry['totp']}")

    lines.append("")
    lines.append("Notes:")

    notes = entry.get("notes", "")

    if notes:
        lines.extend(notes.splitlines())

    return "\n".join(lines) + "\n"


def parse_text(filename):

    fields = {}

    notes = []

    in_notes = False

    with open(filename, "r", encoding="utf-8") as f:

        for line in f:

            line = line.rstrip("\n")

            if line.lower() == "notes:":
                in_notes = True
                continue

            if in_notes:
                notes.append(line)
                continue

            if ":" in line:

                key, value = line.split(":", 1)

                key = key.lower().strip()
                value = value.strip()

                mapping = {
                    "title": "title",
                    "username": "username",
                    "password": "password",
                    "url": "url",
                    "totp": "totp",
                }

                if key in mapping:
                    fields[mapping[key]] = value

    fields["notes"] = "\n".join(notes).rstrip()

    return fields


def edit_entry(entry):

    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".txt",
        dir="/dev/shm",
        delete=False,
        encoding="utf-8",
    ) as f:

        temp_file = f.name

        f.write(entry_to_text(entry))

    # Restrict permissions (owner read/write only)
    os.chmod(temp_file, 0o600)

    try:

        subprocess.run(EDITOR + [temp_file], check=True)

        edited = parse_text(temp_file)

        for key in [
            "title",
            "username",
            "password",
            "url",
            "totp",
            "notes",
        ]:

            if key in edited:

                if edited[key]:

                    entry[key] = edited[key]

                elif key in entry:

                    del entry[key]

    finally:

        if os.path.exists(temp_file):
            os.unlink(temp_file)


def main():

    entries = load_vault()

    if len(os.sys.argv) != 2:

        print("Usage:\n" "  edit_entry.py ID")

        return 1

    entry_id = os.sys.argv[1]

    entry = find_entry(entries, entry_id)

    if not entry:

        print("Entry not found")
        return 1

    edit_entry(entry)

    save_vault(entries)

    print("Entry updated")


if __name__ == "__main__":
    raise SystemExit(main())
