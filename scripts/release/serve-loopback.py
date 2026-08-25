#!/usr/bin/env python3
"""Serve one directory on loopback and publish the selected ephemeral port."""

import functools
import http.server
import os
from pathlib import Path
import sys


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


if len(sys.argv) != 3:
    fail("usage: serve-loopback.py <absolute-directory> <absolute-ready-file>")

root = Path(sys.argv[1])
ready_file = Path(sys.argv[2])
if not root.is_absolute() or not root.is_dir() or root.is_symlink():
    fail("loopback server directory is missing or unsafe")
if not ready_file.is_absolute() or ready_file.exists() or not ready_file.parent.is_dir():
    fail("loopback server ready file is unsafe")

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as server:
    server.daemon_threads = True
    port = server.server_address[1]
    temporary_ready_file = ready_file.with_name(ready_file.name + ".tmp")
    try:
        descriptor = os.open(
            temporary_ready_file,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL,
            0o600,
        )
        with os.fdopen(descriptor, "w", encoding="ascii") as stream:
            stream.write(f"{port}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_ready_file, ready_file)
        server.serve_forever()
    finally:
        try:
            temporary_ready_file.unlink()
        except FileNotFoundError:
            pass
