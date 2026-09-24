#!/usr/bin/env python3
"""Loopback administration for a Super Star Fighter dedicated server (Python 3)."""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import sys


def secret(path, variable, prompt, unattended):
    if path:
        return Path(path).read_text(encoding="utf-8").rstrip("\r\n")
    value = os.environ.get(variable)
    if value:
        return value
    if unattended:
        raise ValueError("Missing credential: use a secret file or " + variable)
    return getpass.getpass(prompt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["status", "players", "kick", "ban", "block", "unblock", "set", "set-password", "restart-match", "shutdown"])
    parser.add_argument("--port", type=int, default=7001)
    parser.add_argument("--admin-password-file")
    parser.add_argument("--new-password-file")
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--timeout", type=float, default=5)
    parser.add_argument("--peer-id", type=int)
    parser.add_argument("--source")
    parser.add_argument("--setting")
    parser.add_argument("--value")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or not 1 <= args.timeout <= 60:
        parser.error("port must be 1024-65535 and timeout 1-60 seconds")
    request = {"command": args.command.replace("-", "_")}
    if args.command in ("kick", "ban"):
        if args.peer_id is None:
            parser.error("--peer-id is required")
        request["peer_id"] = args.peer_id
    if args.command in ("block", "unblock"):
        if not args.source:
            parser.error("--source is required")
        request["source"] = args.source
    if args.command == "set":
        if not args.setting or args.value is None:
            parser.error("--setting and --value are required")
        try:
            value = json.loads(args.value)
        except ValueError:
            value = args.value
        request.update(setting=args.setting, value=value)
    password = secret(args.admin_password_file, "SSF_ADMIN_PASSWORD", "Admin password: ", args.non_interactive)
    if args.command == "set-password":
        request["password"] = secret(args.new_password_file, "SSF_NEW_LOBBY_PASSWORD", "New lobby password: ", args.non_interactive)
    with socket.create_connection(("127.0.0.1", args.port), args.timeout) as sock:
        with sock.makefile("rwb") as stream:
            def receive():
                line = stream.readline(1048577)
                if not line or len(line) > 1048576 or not line.endswith(b"\n"):
                    raise ValueError("Missing or oversized admin response")
                message = json.loads(line)
                if not isinstance(message, dict):
                    raise ValueError("Invalid admin response")
                return message

            def send(message):
                stream.write((json.dumps(message) + "\n").encode("utf-8"))
                stream.flush()

            challenge = receive()
            nonce = challenge.get("challenge", "")
            if challenge.get("event") != "challenge" or not isinstance(nonce, str) or not re.fullmatch("[0-9a-f]{64}", nonce):
                raise ValueError("Invalid authentication challenge")
            proof = hashlib.sha256(("ssf-admin-auth-v1\x1f" + nonce + "\x1f" + password).encode("utf-8")).hexdigest()
            send({"command": "authenticate", "proof": proof})
            if not receive().get("ok"):
                raise ValueError("Admin authentication failed")
            send(request)
            response = receive()
            print(json.dumps(response, indent=2))
            return 0 if response.get("ok") else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, EOFError) as error:
        print("Admin error: " + str(error), file=sys.stderr)
        sys.exit(1)
