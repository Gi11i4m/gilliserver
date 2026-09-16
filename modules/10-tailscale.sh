#!/bin/bash
# Joins the tailnet and offers gilliserver as an exit node. Everything gilliserver
# exposes is reachable over this and nothing is port-forwarded on the router.
set -euo pipefail

# DietPi software ID 58. On a fresh flash dietpi.txt has already installed it; on a
# box repurposed from something else it has not, and refusing to install it here
# just meant the module failed on every run forever.
if ! command -v tailscale >/dev/null; then
	echo "   installing DietPi software 58 (Tailscale)"
	/boot/dietpi/dietpi-software install 58
fi
command -v tailscale >/dev/null || { echo "!! tailscale still not installed"; exit 1; }

systemctl is-enabled tailscaled &>/dev/null || systemctl enable --now tailscaled
systemctl is-active tailscaled &>/dev/null || systemctl start tailscaled

# Forwarding is what makes the exit node actually forward rather than blackhole.
# The file is deployed from config/etc/sysctl.d/; this only has to make it take
# effect without waiting for a reboot.
if [[ "$(sysctl -n net.ipv4.ip_forward)" != 1 ]]; then
	echo "   enabling IP forwarding"
	sysctl -q -p /etc/sysctl.d/99-gilliserver-forwarding.conf || true
fi

# At boot this module runs seconds after tailscaled starts, while the backend is
# still "NoState"/"Starting" — and without this wait it concluded the box was not
# on the tailnet and ran `tailscale up` again on every single boot. That is merely
# wasteful with a reusable key and fatal with a single-use one.
for _ in $(seq 30); do
	state="$(tailscale status --json 2>/dev/null | sed -n 's/.*"BackendState": *"\([A-Za-z]*\)".*/\1/p' | head -1)"
	[[ $state == Running || $state == NeedsLogin ]] && break
	sleep 2
done

# Advertising costs nothing until someone approves the node in the admin console,
# and approval is a click a human makes there — it cannot be done from the box.
# So this is set unconditionally and the approval is simply waited for.
#
# `tailscale set` rather than re-running `tailscale up`: `up` resets every pref you
# do not name on the command line, so using it here would quietly drop --ssh and
# --accept-routes the first time someone adds a flag and forgets the others.
advertise_exit_node() {
	# AdvertiseRoutes holds 0.0.0.0/0 and ::/0 once the node is offering itself.
	if tailscale debug prefs 2>/dev/null | grep -q '0\.0\.0\.0/0'; then
		return 0
	fi
	echo "   advertising as an exit node"
	tailscale set --advertise-exit-node || echo "!! could not advertise exit node"
}

if [[ ${state:-} == Running ]]; then
	echo "   tailscale up as $(tailscale status --self --peers=false 2>/dev/null | head -1)"
	advertise_exit_node
	exit 0
fi

if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
	echo "!! not on the tailnet and no TAILSCALE_AUTHKEY in ${GILLISERVER_ENV:-/boot/gilliserver.env}"
	echo "!! run \`tailscale up\` by hand over ssh, or drop a key in that file"
	exit 1
fi

# --accept-routes so the Pi can reach anything another node advertises;
# --ssh so you can get in over the tailnet without opening port 22 to the LAN;
# --advertise-exit-node so a reflashed box offers itself without a second step.
tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname=gilliserver --ssh \
	--accept-routes --advertise-exit-node
