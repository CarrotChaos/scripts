#!/usr/bin/env bash

virsh --connect qemu:///system start win11
looking-glass-client -m KEY_RIGHTCTRL
