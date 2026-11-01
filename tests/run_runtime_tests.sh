#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
python3 tests/mock_ollama_server.py &
server_pid=$!
cleanup() {
  kill "$server_pid" 2>/dev/null || true
}
trap cleanup EXIT

for attempt in {1..30}; do
  if curl --silent --fail http://127.0.0.1:11434/health >/dev/null; then
    break
  fi
  sleep 0.2
done
curl --silent --fail http://127.0.0.1:11434/health >/dev/null

timeout 60s godot --headless --editor --path . --quit
timeout 60s godot --headless --path . --script res://tests/runtime_smoke.gd
