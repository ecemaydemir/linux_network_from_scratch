#!/usr/bin/env bash
# Seviye 3 topolojisini siler.
set -u

for n in pc1 pc2 r1; do
  ip netns del "$n" 2>/dev/null || true
done

echo "Temizlendi."
