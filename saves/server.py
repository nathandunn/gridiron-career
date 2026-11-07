#!/usr/bin/env python3
"""Cloud saves for Gridiron Career: one JSON career per save code.

    GET  /api/save/<CODE>   -> the newest save (404 if none)
    PUT  /api/save/<CODE>   -> store it (a JSON career, up to 8 MB)

A save code is three groups of four letters/digits (see scripts/cloud.gd); it is the only key
and nothing about the player is kept. Saves live in DATA (a host folder, so they outlive
redeploys): <CODE>.json is the newest, and the last KEEP versions before it are kept as
<CODE>.<unix time>.json in case a bad save ever overwrites a good one.

Standard library only; nginx in the game's container proxies /api/save/ here.
"""
import glob
import json
import os
import re
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA = os.environ.get("SAVES_DIR", "/data")
KEEP = 10
MAX = 8 * 1024 * 1024
CODE = re.compile(r"^/api/save/([A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4})$")


class Handler(BaseHTTPRequestHandler):
    server_version = "gridiron-saves/1"

    def _code(self):
        m = CODE.match(self.path.split("?")[0])
        return m.group(1) if m else None

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        c = self._code()
        if not c:
            return self._send(400, b'{"error":"bad code"}')
        p = os.path.join(DATA, c + ".json")
        if not os.path.exists(p):
            return self._send(404, b'{"error":"no save"}')
        with open(p, "rb") as f:
            self._send(200, f.read())

    def do_PUT(self):
        c = self._code()
        if not c:
            return self._send(400, b'{"error":"bad code"}')
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX:
            return self._send(413, b'{"error":"too big"}')
        body = self.rfile.read(n)
        try:
            d = json.loads(body)
            assert isinstance(d, dict) and "teams" in d
        except Exception:
            return self._send(400, b'{"error":"not a career"}')
        os.makedirs(DATA, exist_ok=True)
        p = os.path.join(DATA, c + ".json")
        # keep the one before as a dated version, and only the last KEEP of those
        if os.path.exists(p):
            os.replace(p, os.path.join(DATA, "%s.%d.json" % (c, int(time.time() * 1000))))
            old = sorted(glob.glob(os.path.join(DATA, c + ".*.json")))
            for q in old[:-KEEP]:
                os.remove(q)
        fd, tmp = tempfile.mkstemp(dir=DATA)
        with os.fdopen(fd, "wb") as f:
            f.write(body)
        os.replace(tmp, p)
        self._send(200, json.dumps({"ok": True, "at": int(time.time())}).encode())

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
