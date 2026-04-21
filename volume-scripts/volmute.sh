#!/bin/sh
pactl set-sink-mute @DEFAULT_SINK@ toggle
pkill -RTMIN+5 dwmblocks

