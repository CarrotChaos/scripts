#!/usr/bin/env python3

import sys
import json
import struct
import socket
import threading

SOCKET_PATH = "/tmp/pass-dmenu.sock"
daemon_socket = None
DEBUG = "/tmp/pass-native-debug.log"

# clear old log
open(DEBUG, "w").close()


def log(msg):
    with open(DEBUG, "a") as f:
        f.write(msg + "\n")


def read_native():

    raw = sys.stdin.buffer.read(4)

    if not raw:
        return None

    length = struct.unpack("@I", raw)[0]

    data = sys.stdin.buffer.read(length)

    return json.loads(data.decode())


def send_native(message):

    data = json.dumps(message).encode()

    sys.stdout.buffer.write(struct.pack("@I", len(data)))

    sys.stdout.buffer.write(data)

    sys.stdout.buffer.flush()

    log(f"TO FIREFOX: {message}")


def daemon_reader():

    buffer = b""

    while True:

        data = daemon_socket.recv(4096)

        if not data:
            break

        buffer += data

        while b"\n" in buffer:

            line, buffer = buffer.split(b"\n", 1)

            message = json.loads(line.decode())

            log(f"FROM DAEMON: {message}")

            send_native(message)


def connect_daemon():

    global daemon_socket

    daemon_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    daemon_socket.connect(SOCKET_PATH)

    daemon_socket.sendall(b'{"type":"native"}\n')

    threading.Thread(target=daemon_reader, daemon=True).start()


connect_daemon()

log("native started")


while True:

    message = read_native()

    if message is None:
        break

    log(f"FROM FIREFOX: {message}")

    daemon_socket.sendall((json.dumps(message) + "\n").encode())
