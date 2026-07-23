#!/usr/bin/env python3

from vault_lib import load_vault, save_vault


def sort_entries(entries):
    return sorted(
        entries,
        key=lambda x: (
            x.get("title", "").casefold(),
            x.get("username", "").casefold(),
        ),
    )


def main():
    entries = load_vault()
    entries = sort_entries(entries)
    save_vault(entries)
    print(f"Sorted {len(entries)} entries")


if __name__ == "__main__":
    main()
