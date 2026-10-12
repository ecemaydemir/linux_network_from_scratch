#!/usr/bin/env bash
# Seviye 7 topolojisini siler.
set -u
for n in pc1 pc2 pc3 pc4 pc5 pc6 r1; do ip netns del "$n" 2>/dev/null || true; done
ip link del sw1-trunk 2>/dev/null || true
ip link del sw1 2>/dev/null || true
ip link del sw2 2>/dev/null || true
echo "Temizlendi."
