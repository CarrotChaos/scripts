#!/bin/sh
# Put this is /etc/elogind/system-sleep/

case "$1" in
post)
	pkill -RTMIN+1 dwmblocks
	;;
esac
