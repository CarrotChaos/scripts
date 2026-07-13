#!/bin/sh

doas cryptsetup open ~/passwords.img passwords
doas mount /dev/mapper/passwords ~/passwords
