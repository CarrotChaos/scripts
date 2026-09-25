#!/bin/sh

. "$HOME/.cache/colors/maybar"

envsubst < "$HOME/.config/maybar/config.yml" | maybar
