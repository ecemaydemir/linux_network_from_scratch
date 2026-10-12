#!/usr/bin/env bash
# Seviye 4: TCP ve UDP deneyleri için Seviye 3'ün çalışır halini kurar.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

command -v nc >/dev/null || { echo "netcat gerekli: sudo apt install -y netcat-openbsd"; exit 1; }
"$DIR/../03-router/setup.sh" --fixed >/dev/null
echo "Hazır. Sunucu: sudo ip netns exec pc2 nc -l 8080 | İstemci: sudo ip netns exec pc1 nc 10.0.20.10 8080"
