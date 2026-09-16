#!/bin/bash
# Joins the tailnet. Everything gilliserver exposes is reachable over this and
# nothing is port-forwarded on the router.
set -euo pipefail

command -v tailscale >/dev/null || {
	echo "tailscale is not installed — /boot/dietpi/dietpi-software install 58"
	exit 1
}

systemctl is-enabled tailscaled &>/dev/null || systemctl enable --now tailscaled

if tailscale status --json | grep -q '"BackendState": *"Running"'; then
	echo "   tailscale up as $(tailscale status --self --peers=false 2>/dev/null | head -1)"
	exit 0
fi

if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
	echo "!! not on the tailnet and no TAILSCALE_AUTHKEY in /boot/gilliserver.env"
	echo "!! run \`tailscale up\` by hand over ssh, or drop a key in that file"
	exit 1
fi

# --accept-routes so the Pi can reach anything another node advertises;
# --ssh so you can get in over the tailnet without opening port 22 to the LAN.
tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname=gilliserver --ssh --accept-routes
