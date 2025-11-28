#!/usr/bin/env bash
set -euo pipefail

# Run Franky Remote Server
echo "Starting Franky Remote Server (Gen1)..."

cd "$HOME/franky-remote"
micromamba run -n franky-gen1 python3 server/run.py --persistent
