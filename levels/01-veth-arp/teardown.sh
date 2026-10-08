#!/usr/bin/env bash
# Seviye 1 topolojisini siler. Namespace silinince veth çifti de silinir.
set -u

ip netns del pc1 2>/dev/null || true
ip netns del pc2 2>/dev/null || true

echo "Temizlendi."
