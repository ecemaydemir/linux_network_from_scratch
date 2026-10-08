#!/usr/bin/env bash
# Seviye 2 topolojisini siler.
set -u

for i in 1 2 3; do
  ip netns del "pc$i" 2>/dev/null || true
done
ip link del br0 2>/dev/null || true

echo "Temizlendi."
