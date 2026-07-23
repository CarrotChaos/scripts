#!/usr/bin/env python3

import sys


def parse_yaml_simple(filename):

    entries = []
    current = None

    with open(filename, "r", encoding="utf-8") as f:

        for line in f:

            line = line.rstrip()

            if line.startswith("  - "):

                if current:
                    entries.append(current)

                current = {}

                line = line[4:]

                key, value = line.split(":", 1)
                current[key.strip()] = unquote(value.strip())

            elif line.startswith("    ") and current:

                key, value = line.strip().split(":", 1)

                current[key] = unquote(value.strip())

    if current:
        entries.append(current)

    return entries


def unquote(value):

    if value.startswith('"') and value.endswith('"'):

        value = value[1:-1]

        value = value.replace("\\n", "\n")
        value = value.replace('\\"', '"')
        value = value.replace("\\\\", "\\")

    return value


def yaml_escape(value):

    value = str(value)

    value = value.replace("\\", "\\\\")
    value = value.replace('"', '\\"')
    value = value.replace("\n", "\\n")

    return f'"{value}"'


def write_yaml(entries, filename):

    with open(filename, "w", encoding="utf-8") as f:

        f.write("entries:\n")

        for entry in entries:

            f.write("  - id: " + yaml_escape(entry.get("id", "")) + "\n")

            for key in [
                "title",
                "username",
                "password",
                "notes",
                "url",
                "totp",
            ]:

                if key in entry and entry[key]:

                    f.write(f"    {key}: {yaml_escape(entry[key])}\n")

            f.write("\n")


def sort_entries(entries):

    return sorted(
        entries,
        key=lambda x: (x.get("title", "").lower(), x.get("username", "").lower()),
    )


if __name__ == "__main__":

    if len(sys.argv) != 3:

        print("Usage:\n" "  python3 sort_vault.py INPUT.yaml OUTPUT.yaml")

        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]

    entries = parse_yaml_simple(input_file)

    entries = sort_entries(entries)

    write_yaml(entries, output_file)

    print(f"Sorted {len(entries)} entries")
