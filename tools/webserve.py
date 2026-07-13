#!/usr/bin/env python3
"""Static file server that disables caching — so redeployed Flutter web builds
are always picked up on refresh (no stale main.dart.js)."""
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    directory = sys.argv[2] if len(sys.argv) > 2 else "."
    import os

    os.chdir(directory)
    ThreadingHTTPServer(("0.0.0.0", port), NoCacheHandler).serve_forever()
