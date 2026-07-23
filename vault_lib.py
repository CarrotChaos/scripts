#!/usr/bin/env python3

import json

VAULT_FILE = "/dev/shm/passwords.json"


def load_vault(filename=VAULT_FILE):
    try:
        with open(filename, encoding="utf-8") as f:
            vault = json.load(f)
    except FileNotFoundError:
        return []
    return vault.get("entries", [])


def save_vault(entries, filename=VAULT_FILE):
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(
            {"entries": entries},
            f,
            indent=4,
            ensure_ascii=False,
        )
