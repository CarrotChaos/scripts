#!/usr/bin/env python3

import sys
from vault_lib import load_vault


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

    entries = load_vault()
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
