#!/bin/bash
# Local server — no ngrok tunnel.
# Run with: bash start.sh

set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in values."
  exit 1
fi

echo "Starting Rastarant API server (local)..."
echo "URL: http://localhost:8000"
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [ -n "$LAN_IP" ]; then
  echo "LAN menu QR: http://$LAN_IP:8000/menu"
fi
echo "Docs: http://localhost:8000/docs"
echo ""

if [ -d .local_pg_data ]; then
  if ! /usr/lib/postgresql/18/bin/pg_isready -h localhost -p 55432 >/dev/null 2>&1; then
    mkdir -p .local_pg_logs .local_pg_socket
    /usr/lib/postgresql/18/bin/pg_ctl \
      -D .local_pg_data \
      -l .local_pg_logs/postgres.log \
      -o "-p 55432 -k $(pwd)/.local_pg_socket" \
      start
  fi
fi

NGROK_AUTHTOKEN="" NGROK_STATIC_DOMAIN="" python3 main.py
