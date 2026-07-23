#!/usr/bin/env python3

import sys
from vault_lib import load_vault, save_vault


def set_totp(entry_id, secret):
    entries = load_vault()
    for e in entries:
        if e["id"] == entry_id:
            e["totp"] = secret
            save_vault(entries)
            return

    print("Entry not found")
    sys.exit(1)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage:\n" "  totp_edit.py ID SECRET")
        sys.exit(1)
    set_totp(sys.argv[1], sys.argv[2])
