#!/bin/sh
set -e

DOTFILES="$HOME/dotfiles"

# Link top-level dotfiles.
for file in .bashrc .Xresources; do
    if [ -e "$DOTFILES/$file" ]; then
        ln -sf "$DOTFILES/$file" "$HOME/$file"
    fi
done

# Link configuration files and directories.
mkdir -p "$HOME/.config"

for item in "$DOTFILES"/.config/*; do
    [ -e "$item" ] || continue
    name=${item##*/}
    ln -sfn "$item" "$HOME/.config/$name"
done
