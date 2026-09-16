#!/bin/bash
# Runs once, on the DietPi's very first boot, after its own installs are done.
#
# Everything it does is "get this repo onto the box and hand over to it". All real
# configuration lives in the repo, so this file should almost never need to change.
set -euo pipefail

REPO_URL="${GILLISERVER_REPO:-https://github.com/Gi11i4m/gilliserver.git}"
REPO_DIR=/opt/gilliserver

exec > >(tee -a /root/.gilliserver-bootstrap.log) 2>&1
echo "=== gilliserver bootstrap $(date -Is) ==="

# Secrets live on the boot partition, not in the repo: you can write them from a
# laptop by re-inserting the SD card, and they survive a wipe of /opt.
[[ -f /boot/gilliserver.env ]] || cp /boot/gilliserver.env.example /boot/gilliserver.env 2>/dev/null || true

command -v git >/dev/null || { apt-get update && apt-get install -y git; }

if [[ -d $REPO_DIR/.git ]]; then
	git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
else
	git clone "$REPO_URL" "$REPO_DIR"
fi

exec "$REPO_DIR/scripts/apply.sh"
