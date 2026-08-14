#!/usr/bin/env bash
set -e

VM="win11"

virsh --connect qemu:///system shutdown "$VM"

echo "Waiting for $VM to shut down..."
while [[ "$(virsh --connect qemu:///system domstate "$VM")" != "shut off" ]]; do
	sleep 1
done
