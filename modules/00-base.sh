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

# /boot/gilliserver.env holds an auth key and API keys.
[[ -f /boot/gilliserver.env ]] && chmod 600 /boot/gilliserver.env || true
