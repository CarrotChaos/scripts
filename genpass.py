#!/usr/bin/env python3

import argparse
import secrets
import string
from pathlib import Path


def generate_password(length: int, use_symbols: bool = True) -> str:
    if length <= 0:
        raise ValueError("Password length must be greater than 0")

    chars = string.ascii_letters + string.digits

    if use_symbols:
        chars += string.punctuation

    return "".join(secrets.choice(chars) for _ in range(length))


def replace_password(file_path: str, password: str):
    path = Path(file_path)

    # Create parent directories if needed
    path.parent.mkdir(parents=True, exist_ok=True)

    if path.exists():
        lines = path.read_text().splitlines()
        if lines:
            lines[0] = password
        else:
            lines = [password]
    else:
        lines = [password]

    path.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Generate a cryptographically secure password."
    )

    parser.add_argument(
        "file", nargs="?", help="Password file to update (replaces first line)"
    )

    parser.add_argument(
        "-l", "--length", type=int, default=25, help="Password length (default: 25)"
    )

    parser.add_argument("--no-symbols", action="store_true", help="Exclude symbols")

    args = parser.parse_args()

    password = generate_password(args.length, use_symbols=not args.no_symbols)

    if args.file:
        replace_password(args.file, password)
    else:
        print(password)


if __name__ == "__main__":
    main()
