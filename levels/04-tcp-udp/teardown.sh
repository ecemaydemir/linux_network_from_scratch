#!/usr/bin/env bash
# Seviye 4 topolojisini siler.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/../03-router/teardown.sh"
