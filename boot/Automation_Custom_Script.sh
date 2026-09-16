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

command -v git >/dev/null || { apt-get update && apt-get install -y git; }

if [[ -d $REPO_DIR/.git ]]; then
	git -C "$REPO_DIR" remote set-url origin "$REPO_URL"
else
	git clone "$REPO_URL" "$REPO_DIR"
fi

# Secrets live on the boot partition, not in the repo: you can write them from a
# laptop by re-inserting the SD card, and they survive a wipe of /opt. Normally
# setup/prepare-sdcard.sh has already put one there; this is the fallback for a
# card that was flashed without it, so that the file at least exists to be filled.
#
# Which mount point that is depends on the image — the Bookworm RPi images put the
# FAT partition at /boot/firmware and leave /boot on ext4. apply.sh works the same
# thing out at runtime. Has to come after the clone: the template is in the repo.
BOOT=/boot
[[ "$(findmnt -n -o FSTYPE --target /boot/firmware 2>/dev/null)" == vfat ]] && BOOT=/boot/firmware
if [[ ! -f /boot/gilliserver.env && ! -f /boot/firmware/gilliserver.env ]]; then
	cp "$REPO_DIR/boot/gilliserver.env.example" "$BOOT/gilliserver.env" || true
	chmod 600 "$BOOT/gilliserver.env" || true
	echo "!! created an empty $BOOT/gilliserver.env — fill in TAILSCALE_AUTHKEY"
fi

exec "$REPO_DIR/scripts/apply.sh"
