#!/bin/bash
# Lets gilliserver wake sleeping machines on the LAN — the Steam Machine first,
# anything in /etc/gilliserver/devices.conf after that.
#
# This is the whole reason the Pi is always on: it is the one box on the LAN that
# never sleeps, so it can be the one that sends the magic packet.
#
# The tools themselves are installed by modules/05-packages.sh; this only checks,
# so that a missing one is reported against wake-on-lan rather than silently
# breaking `gilli-wake` at 2am.
set -euo pipefail

command -v wakeonlan >/dev/null || { echo "!! wakeonlan missing — see modules/05-packages.sh"; exit 1; }

# The placeholder that ships in config/etc/gilliserver/devices.conf. Saying so once
# an hour is the only way anyone finds out WoL was never actually set up.
if grep -q '00:00:00:00:00:00' /etc/gilliserver/devices.conf 2>/dev/null; then
	echo "!! /etc/gilliserver/devices.conf still has the placeholder MAC — gilli-wake will do nothing"
fi
