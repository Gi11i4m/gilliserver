#!/bin/bash
# Everything boot/dietpi.overrides installs on a *first* boot, made true on every
# boot instead.
#
# AUTO_SETUP_INSTALL_SOFTWARE_ID and AUTO_SETUP_APT_INSTALLS in dietpi.txt only
# ever run once, during DietPi's first-boot setup. A box that was reflashed gets
# them; a box repurposed from something else — which is how gilliserver itself
# started life, as a meeting-room kiosk — never does. Without this module the two
# never converge and you find out months later, when a module needs `etherwake`.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Kept in step with AUTO_SETUP_APT_INSTALLS in boot/dietpi.overrides.
#   bubblewrap  sandboxes the agent terminals Omnigent launches (Linux only)
#   tmux        Omnigent's harnesses (`omni claude`, `omni codex`) launch into it
#   etherwake   a second way to send a magic packet when wakeonlan's is ignored
APT_PACKAGES=(curl ca-certificates etherwake wakeonlan tmux bubblewrap)

missing=()
for pkg in "${APT_PACKAGES[@]}"; do
	dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing+=("$pkg")
done

if [[ ${#missing[@]} -gt 0 ]]; then
	echo "   installing: ${missing[*]}"
	apt-get update -qq
	apt-get install -y "${missing[@]}"
fi

# DietPi software IDs, from boot/dietpi.overrides. 58 (Tailscale) is left to
# modules/10-tailscale.sh, which has to join the tailnet right after installing it.
#   105  OpenSSH Server — DietPi's Dropbear default has no sftp/scp
#   152  Avahi-Daemon   — makes `gilliserver.local` resolve on the LAN
DIETPI_SOFTWARE_IDS=(105 152)

# DietPi records install state in this file as aSOFTWARE_INSTALL_STATE[<id>]=2.
dietpi_installed() {
	grep -q "^aSOFTWARE_INSTALL_STATE\[$1\]=2$" /boot/dietpi/.installed 2>/dev/null
}

for id in "${DIETPI_SOFTWARE_IDS[@]}"; do
	dietpi_installed "$id" && continue
	echo "   installing DietPi software $id"
	/boot/dietpi/dietpi-software install "$id" || echo "!! DietPi software $id failed"
done
