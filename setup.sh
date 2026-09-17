#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(uname -m)" != x86_64 ]; then echo 'Requires x86-64 Ubuntu 22.04 (native or WSL2).'; exit 1; fi
for asset in runtime.tar.gz toolchain.tar.gz preparation-support.tar.gz; do
 if [ ! -f "$asset" ]; then
  command -v gh >/dev/null || { echo 'Install gh and authenticate (README), or download both release archives manually.'; exit 1; }
  gh release download v1.0.0 --repo le21-j/pluto-environment-collector --pattern "$asset"
 fi
done
sudo apt-get update
sudo apt-get install -y python3-venv python3-dev build-essential proot openssh-client
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python bootstrap.py
python3 collect.py --check
