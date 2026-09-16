#!/bin/bash
# Installs the Omnigent CLI (omnigent.ai) and runs it as gilliserver-omnigent.service.
#
# Verified on the real Pi 3 B: `uv tool install` takes about 40 seconds, the server
# needs ~50 seconds before it serves its first request, and it idles around 270 MB
# — comfortable in 1 GB, and it never touched swap. What the upstream install.sh
# does is not reproduced here: it is interactive, it re-downloads on every run
# (`uv tool install --force`), and it edits ~/.bashrc. This module does the same
# work idempotently.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

UV=/root/.local/bin/uv
export PATH="/root/.local/bin:$PATH"

# uv is the whole install mechanism: it fetches its own CPython 3.12 (Debian 12
# only has 3.11, and Omnigent needs 3.12+) and puts `omni` in ~/.local/bin.
if [[ ! -x $UV ]]; then
	echo "   installing uv"
	curl -LsSf https://astral.sh/uv/install.sh | sh
fi
[[ -x $UV ]] || { echo "!! uv did not install"; exit 1; }

# No --force, unlike upstream's installer: this runs every hour, and --force means
# re-downloading the wheel and rebuilding the venv sixty times a day. Upgrades are
# a deliberate act — `uv tool upgrade omnigent` — not something a timer does behind
# your back to a server that might be mid-session.
if ! command -v omni >/dev/null; then
	echo "   installing omnigent"
	"$UV" tool install -q --python 3.12 omnigent
fi
command -v omni >/dev/null || { echo "!! omni installed but not on PATH"; exit 1; }

# Node, tmux and bubblewrap are what the harnesses (`omni claude`, `omni codex`)
# need; the server itself runs without them. Warn rather than fail — a missing one
# should not stop the server from coming up.
for tool in node tmux bwrap; do
	command -v "$tool" >/dev/null || echo "!! $tool missing — \`omni claude\`/\`omni codex\` need it"
done

# apply.sh only reloads the systemd daemon; restarting what a module owns is the
# module's job. Restart when the unit file itself changed, so a config change lands
# without waiting for a reboot.
#
# The comparison is a stored hash rather than a timestamp: a marker under /run is
# gone after a reboot, which made this restart a perfectly healthy server on every
# single boot.
unit=/etc/systemd/system/gilliserver-omnigent.service
stamp=/var/lib/gilliserver/omnigent-unit.sha

if [[ -f $unit ]]; then
	mkdir -p "$(dirname "$stamp")"
	now="$(sha256sum "$unit" | cut -d' ' -f1)"
	was="$(cat "$stamp" 2>/dev/null || true)"

	if ! systemctl is-active --quiet gilliserver-omnigent; then
		echo "   starting gilliserver-omnigent"
		systemctl start gilliserver-omnigent || echo "!! gilliserver-omnigent failed to start"
	elif [[ $now != "$was" ]]; then
		echo "   unit changed, restarting gilliserver-omnigent"
		systemctl restart gilliserver-omnigent || echo "!! gilliserver-omnigent failed to restart"
	fi
	echo "$now" > "$stamp"
fi

# Serve it over HTTPS on the tailnet.
#
# Omnigent speaks plain HTTP, so https://gilliserver.tail2b0581.ts.net:6767/ fails
# the TLS handshake outright ("wrong version number") — the obvious URL to try, and
# it looks like the box is down rather than like the wrong scheme. `tailscale
# serve` terminates TLS with a real Let's Encrypt certificate for the MagicDNS name
# and proxies to the local port, so the working URL is just
# https://gilliserver.tail2b0581.ts.net/ with no port at all.
#
# The backend stays bound to 0.0.0.0 rather than 127.0.0.1 on purpose: Omnigent
# only switches into accounts mode (username + password) when it sees a non-local
# bind, and serve is reachable by everyone on the tailnet. Binding it back to
# localhost would drop the login and hand the whole tailnet an unauthenticated
# server. serve is tailnet-only — it is not `funnel`, nothing is public.
if systemctl is-active --quiet tailscaled && tailscale status --json 2>/dev/null | grep -q '"BackendState": *"Running"'; then
	if ! tailscale serve status 2>/dev/null | grep -q '127.0.0.1:6767'; then
		echo "   serving omnigent over https on the tailnet"
		tailscale serve --bg --https=443 http://127.0.0.1:6767 ||
			echo "!! tailscale serve failed — is HTTPS enabled for the tailnet?"
	fi
fi
