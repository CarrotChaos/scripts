#!/bin/sh

doas /usr/bin/cryptsetup open ~/passwords.img passwords
doas /usr/bin/mount /dev/mapper/passwords ~/passwords
