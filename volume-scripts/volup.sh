#!/bin/sh
pactl set-sink-volume @DEFAULT_SINK@ +1%
pkill -RTMIN+5 dwmblocks

