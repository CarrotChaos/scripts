#!/usr/bin/env bash

set -euo pipefail

PYTHON_PID=""

RECEIVE_PIPE="/tmp/extension_to_bash_pipe"
SEND_PIPE="/tmp/bash_to_extension_pipe"

start_bridge() {
	rm -f "$RECEIVE_PIPE" "$SEND_PIPE"

	mkfifo "$RECEIVE_PIPE"
	mkfifo "$SEND_PIPE"

	python3 ws_server.py "$RECEIVE_PIPE" "$SEND_PIPE" &
	PYTHON_PID=$!

	echo "Bash: started Python server PID=$PYTHON_PID"
}

stop_bridge() {
	echo "Bash: cleaning up"

	if [[ -n "$PYTHON_PID" ]]; then
		kill "$PYTHON_PID" 2>/dev/null || true
	fi

	rm -f "$RECEIVE_PIPE" "$SEND_PIPE"
}

receive_extension_message() {
	local message

	echo "Bash: waiting for extension message..."

	read -r message <"$RECEIVE_PIPE"

	EXTENSION_MESSAGE="$message"

	echo "Bash received:"
	echo "$EXTENSION_MESSAGE"

	if command -v jq >/dev/null; then
		EXTENSION_EVENT=$(jq -r '.event' <<<"$EXTENSION_MESSAGE")
		EXTENSION_VALUE=$(jq -r '.value' <<<"$EXTENSION_MESSAGE")
	fi
}

send_extension_message() {
	local message="$1"

	echo "$message" >"$SEND_PIPE"

	echo "Bash sent:"
	echo "$message"
}

trap stop_bridge EXIT

start_bridge

#
# Wait for Firefox -> Bash first
#
receive_extension_message

if command -v jq >/dev/null; then

	event=$(jq -r '.event' <<<"$EXTENSION_MESSAGE")
	value=$(jq -r '.value' <<<"$EXTENSION_MESSAGE")

	echo "Event: $event"
	echo "Value: $value"

fi

#
# Respond back
#
send_extension_message \
	'{"event":"bash_response","value":"hello from bash"}'

echo "Bash: done"

sleep 5
