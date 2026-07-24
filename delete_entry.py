#!/usr/bin/env python3

import sys
from vault_lib import load_vault, save_vault


def delete_entry(entry_id):

    entries = load_vault()

    new_entries = [entry for entry in entries if entry.get("id") != entry_id]

    if len(new_entries) == len(entries):
        print("Entry not found.")
        sys.exit(1)

    save_vault(new_entries)

    print("Entry deleted.")


if __name__ == "__main__":

    if len(sys.argv) != 2:
        print("Usage:\n" "  delete_entry.py ID")
        sys.exit(1)

    delete_entry(sys.argv[1])
