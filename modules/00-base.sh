#!/bin/bash
# Housekeeping that every later module assumes is done.
set -euo pipefail

# Unattended apt: apply.sh runs while nobody is watching, so a package that wants
# to ask about a changed config file would hang the whole run instead.
export DEBIAN_FRONTEND=noninteractive

# NTP as a daemon, not a one-shot at boot. Same reason as in boot/dietpi.overrides:
# a clock stuck in the past makes every `git pull` fail on certificate validation.
if [[ "$(timedatectl show -p NTPSynchronized --value)" != yes ]]; then
	/boot/dietpi/func/dietpi-set_software ntpd-mode 4 || true
fi

# Headless: never boot into a display manager. A fresh flash gets this from
# AUTO_SETUP_AUTOSTART_TARGET_INDEX=7, but a box repurposed from something that
# ran a desktop comes with graphical.target as its default and keeps it forever.
if [[ "$(systemctl get-default)" != multi-user.target ]]; then
	echo "   default target was $(systemctl get-default), setting multi-user.target"
	systemctl set-default multi-user.target
fi

# Holds the Tailscale auth key and API keys. apply.sh works out which partition it
# is on (/boot or /boot/firmware) and exports the path.
#
# On a FAT32 boot partition this does nothing — vfat has no permission bits, so the
# file reads 755 whatever you ask for. That is the price of a secrets file you can
# edit from a laptop with the SD card in hand, and it is why the only thing in
# there is keys that can be revoked. The chmod still matters on an ext4 /boot.
env_file="${GILLISERVER_ENV:-/boot/gilliserver.env}"
[[ -f $env_file ]] && chmod 600 "$env_file" 2>/dev/null || true
