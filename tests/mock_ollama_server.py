#!/usr/bin/env python3
"""Minimal Ollama-compatible HTTP endpoint for deterministic integration tests."""

from http.server import BaseHTTPRequestHandler, HTTPServer
import json


ACTION = {
    "narration": "Edda studies your face, then lowers her spear.",
    "action": "persuade",
    "ability": "charisma",
    "target": "Warden Edda",
    "dc": 12,
    "consequence_on_success": "She opens the gate.",
    "consequence_on_failure": "She grows more suspicious.",
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ready")
            return
        self.send_error(404)

    def do_POST(self):
        if self.path != "/api/chat":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        if request.get("model") != "test-model" or request.get("stream") is not False:
            self.send_error(400, "Unexpected model request")
            return
        if not isinstance(request.get("format"), dict) or "messages" not in request:
            self.send_error(400, "Expected structured chat request")
            return
        response = {"message": {"role": "assistant", "content": json.dumps(ACTION)}}
        body = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format, *_args):
        pass


HTTPServer(("127.0.0.1", 11434), Handler).serve_forever()
