#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -m)" != x86_64 ]; then echo 'Requires x86-64 Ubuntu 22.04 (native or WSL2).'; exit 1; fi
sudo apt-get update
sudo apt-get install -y python3-venv python3-dev build-essential proot openssh-client curl ca-certificates
for asset in runtime.tar.gz toolchain.tar.gz preparation-support.tar.gz fixed-pure-support.tar.gz; do
 if [ ! -f "$asset" ]; then
  curl --fail --location --retry 3 --output "$asset.partial" "https://github.com/le21-j/pluto-environment-collector/releases/download/v1.0.0/$asset"
  mv "$asset.partial" "$asset"
 fi
done
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
if [ ! -d .runtime ]; then
 .venv/bin/python bootstrap.py
else
 .venv/bin/python bootstrap.py --update
fi
chmod +x bin/wsl
python3 collect.py --check
