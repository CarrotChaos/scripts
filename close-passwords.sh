#!/bin/sh

doas umount ~/passwords
doas cryptsetup close passwords
