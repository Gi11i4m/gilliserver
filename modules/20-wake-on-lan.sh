#!/bin/bash
# Lets gilliserver wake sleeping machines on the LAN — the Steam Machine first,
# anything in /etc/gilliserver/devices.conf after that.
#
# This is the whole reason the Pi is always on: it is the one box on the LAN that
# never sleeps, so it can be the one that sends the magic packet.
set -euo pipefail

command -v wakeonlan >/dev/null || { apt-get update -qq && apt-get install -y wakeonlan; }
