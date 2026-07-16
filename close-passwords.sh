#!/bin/sh

doas /usr/bin/umount ~/passwords
doas /usr/bin/cryptsetup close passwords
