#!/usr/bin/env bash
set -euo pipefail

# Run Franky Remote Server
echo "Starting Franky Remote Server (FR3)..."

cd "$HOME/franky-remote"
micromamba run -n franky-fr3 python3 server/run.py
