#!/usr/bin/env python3

import sys

VAULT_FILE = "/dev/shm/passwords.yaml"


def unquote(value):

    if value.startswith('"') and value.endswith('"'):

        value = value[1:-1]

        value = value.replace("\\n", "\n")
        value = value.replace('\\"', '"')
        value = value.replace("\\\\", "\\")

    return value


def load_vault(filename):

    entries = []

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


def display_name(entry):

    title = entry.get("title", "Untitled")

    username = entry.get("username", "")

    if username:

        return f"{title} ({username})"

    return title


def find_entry(entries, entry_id):

    for entry in entries:

        if entry.get("id") == entry_id:

            return entry

    return None


def unique_display_names(entries):

    names = {}

    result = []

    for entry in entries:

        name = display_name(entry)

        if name not in names:

            names[name] = 1
            result.append(name)

        else:

            names[name] += 1

            result.append(f"{name} [{names[name]}]")

    return result


def get_id_from_display(entries, selected):

    displays = unique_display_names(entries)

    for entry, display in zip(entries, displays):

        if display == selected:

            return entry.get("id", "")

    return ""


def main():

    if len(sys.argv) < 2:

        print(
            "Usage:\n"
            "  vault_query.py list\n"
            "  vault_query.py id DISPLAY\n"
            "  vault_query.py get ID FIELD"
        )

        sys.exit(1)

    entries = load_vault(VAULT_FILE)

    command = sys.argv[1]

    if command == "list":

        for name in unique_display_names(entries):

            print(name)

    elif command == "id":

        if len(sys.argv) != 3:

            sys.exit(1)

        selected = sys.argv[2]

        print(get_id_from_display(entries, selected))

    elif command == "get":

        if len(sys.argv) != 4:

            sys.exit(1)

        entry_id = sys.argv[2]

        field = sys.argv[3]

        entry = find_entry(entries, entry_id)

        if entry:

            print(entry.get(field, ""))

    else:

        print("Unknown command")

        sys.exit(1)


if __name__ == "__main__":

    main()
