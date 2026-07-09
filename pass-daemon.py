#!/usr/bin/env python3

import json
import os
import selectors
import socket
import uuid

SOCKET_PATH = "/tmp/pass-dmenu.sock"

if os.path.exists(SOCKET_PATH):
    os.unlink(SOCKET_PATH)

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(SOCKET_PATH)
server.listen()
os.chmod(SOCKET_PATH, 0o600)

sel = selectors.DefaultSelector()

sel.register(server, selectors.EVENT_READ)

native = None
pending = {}


print("pass-daemon listening", flush=True)


def send(sock, obj):
    try:
        sock.sendall((json.dumps(obj) + "\n").encode())
        return True

    except OSError as e:
        print(f"SEND FAILED: {e}", flush=True)
        return False


while True:

    for key, _ in sel.select():

        #
        # New connection
        #
        if key.fileobj is server:

            conn, _ = server.accept()

            conn.setblocking(False)

            sel.register(conn, selectors.EVENT_READ, data={"buffer": b""})

            continue

        conn = key.fileobj
        state = key.data

        chunk = conn.recv(4096)

        if not chunk:

            if conn is native:
                print("native disconnected", flush=True)
                native = None

            sel.unregister(conn)
            conn.close()
            continue

        state["buffer"] += chunk

        while b"\n" in state["buffer"]:

            line, state["buffer"] = state["buffer"].split(b"\n", 1)

            message = json.loads(line)
            print("MESSAGE:", message, flush=True)

            #
            # Native host announces itself
            #

            if message.get("type") == "native":

                native = conn

                print("native connected", flush=True)

                continue

            #
            # Reply from Firefox
            #

            if "reply_to" in message:

                client = pending.pop(message["reply_to"], None)

                if client:

                    ok = send(client, message)

                    if not ok:
                        try:
                            sel.unregister(client)
                        except Exception:
                            pass

                        try:
                            client.close()
                        except Exception:
                            pass

                continue

            #
            # Request from bash
            #

            request_id = str(uuid.uuid4())

            pending[request_id] = conn

            message["id"] = request_id

            if native is None:

                send(conn, {"error": "firefox not connected"})

                pending.pop(request_id, None)

                continue

            print("FORWARDING TO FIREFOX:", message, flush=True)
            send(native, message)
