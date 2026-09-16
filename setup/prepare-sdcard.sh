#!/bin/bash
# Prepares a freshly flashed DietPi SD card so its first boot configures itself.
#
#   setup/prepare-sdcard.sh [/Volumes/bootfs]
#
# Applies boot/dietpi.overrides onto the card's stock dietpi.txt, copies the
# first-boot bootstrap, and makes sure a secrets file is there for you to fill in.
# Idempotent: running it twice on the same card is fine.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOT="${1:-}"

if [[ -z $BOOT ]]; then
	# DietPi's boot partition mounts under a couple of different names depending on
	# the image and the OS doing the mounting.
	# UNVERIFIED on a current image: on the running Pi the FAT partition is mounted
	# at /boot/firmware and holds only the RPi firmware, while dietpi.txt sits on
	# ext4 at /boot — which a laptop cannot mount. If this search comes up empty on
	# a freshly flashed card, that is why, and the fix is to find out where DietPi
	# puts dietpi.txt before first boot rather than to widen this list blindly.
	for candidate in /Volumes/bootfs /Volumes/boot /Volumes/DIETPI /media/"$USER"/bootfs; do
		[[ -f $candidate/dietpi.txt ]] && BOOT=$candidate && break
	done
fi

[[ -n $BOOT && -f $BOOT/dietpi.txt ]] || {
	echo "no DietPi boot partition found. Flash the card first, then pass its mount point:"
	echo "  setup/prepare-sdcard.sh /Volumes/bootfs"
	exit 1
}
echo "-> using $BOOT"

# Apply our overrides onto the stock dietpi.txt, key by key, so every key we do
# not mention keeps DietPi's default.
while IFS= read -r line; do
	[[ $line =~ ^[A-Z] ]] || continue
	key=${line%%=*}
	if grep -q "^$key=" "$BOOT/dietpi.txt"; then
		sed -i.bak "s|^$key=.*|$line|" "$BOOT/dietpi.txt"
	else
		echo "$line" >> "$BOOT/dietpi.txt"
	fi
	echo "   $line"
done < "$REPO_DIR/boot/dietpi.overrides"
rm -f "$BOOT/dietpi.txt.bak"

cp "$REPO_DIR/boot/Automation_Custom_Script.sh" "$BOOT/Automation_Custom_Script.sh"
chmod +x "$BOOT/Automation_Custom_Script.sh"
echo "   Automation_Custom_Script.sh"

if [[ ! -f $BOOT/gilliserver.env ]]; then
	cp "$REPO_DIR/boot/gilliserver.env.example" "$BOOT/gilliserver.env"
	echo
	echo "!! fill in $BOOT/gilliserver.env before booting (TAILSCALE_AUTHKEY at least)"
fi

# WiFi is optional: ethernet is the safer default for a box that has to come back
# up on its own after a power cut.
if [[ -f $REPO_DIR/boot/dietpi-wifi.txt ]]; then
	cp "$REPO_DIR/boot/dietpi-wifi.txt" "$BOOT/dietpi-wifi.txt"
	echo "   dietpi-wifi.txt"
fi

echo
echo "done. Eject the card, boot the Pi on ethernet, and wait — the first boot"
echo "installs DietPi's own software before it ever reaches our bootstrap."
echo "Follow along with: ssh root@gilliserver.local 'tail -f /root/.gilliserver-bootstrap.log'"
