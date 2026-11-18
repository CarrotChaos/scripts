#!/bin/sh

case "$1/$2" in
post/*)
	pkill -SIGUSR1 dwmblocks
	;;
esac
