#!/usr/bin/env python3

import os
import sys

VAULT_FILE = "/dev/shm/passwords.yaml"


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


def set_totp(entries, entry_id, secret):

    for entry in entries:

        if entry.get("id") == entry_id:

            entry["totp"] = secret
            return True

    return False


def main():

    if len(sys.argv) != 4:

        print("Usage:\n" "  vault_edit.py set-totp ID SECRET")

        sys.exit(1)

    command = sys.argv[1]
    entry_id = sys.argv[2]
    value = sys.argv[3]

    entries = load_vault(VAULT_FILE)

    if command == "set-totp":

        if not set_totp(entries, entry_id, value):

            print("Entry not found")
            sys.exit(1)

    else:

        print("Unknown command")
        sys.exit(1)

    save_vault(VAULT_FILE, entries)


if __name__ == "__main__":
    main()
