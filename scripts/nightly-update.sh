#!/bin/bash
# Everything gilliserver updates about itself, once a night. Run from
# gilliserver-update.timer; safe to run by hand.
#
# This is deliberately NOT part of apply.sh. apply.sh runs hourly and has to stay
# fast and predictable — a box that might spend twenty minutes in apt, restart
# Omnigent and then reboot is not something you want firing every hour, and not
# something you want triggered by pushing a config change.
#
# Each step is independent: a failure is reported and the rest still runs. The one
# thing that is never skipped is the log.
set -uo pipefail

LOG=/root/.gilliserver-update.log

# Same reason as apply.sh: DietPi keeps /var/log in RAM, so anything journald wrote
# about a run that ended in a reboot — and this one can end in a reboot — is gone
# before anyone can read it.
exec > >(tee -a "$LOG") 2>&1
echo "=== update $(date -Is) ==="

export DEBIAN_FRONTEND=noninteractive
export HOME="${HOME:-/root}"

failed=()
step() { echo "-> $1"; }
fail() { echo "!! $1"; failed+=("$1"); }

# ── apt ───────────────────────────────────────────────────────────────────────
# full-upgrade rather than a security-only unattended-upgrades run: this box wants
# to be current, and running both would only mean two things fighting over the apt
# lock. --force-confold keeps our own config files — every one of them is deployed
# from this repo, so a package's version of the file is never the one we want.
#
# Lock::Timeout because the hourly apply may be in apt at the same moment; waiting
# ten minutes is better than failing the night's update over a race.
step "apt update"
apt-get -o DPkg::Lock::Timeout=600 update -qq || fail "apt update"

step "apt full-upgrade"
apt-get -o DPkg::Lock::Timeout=600 \
	-o Dpkg::Options::=--force-confdef \
	-o Dpkg::Options::=--force-confold \
	-y full-upgrade || fail "apt full-upgrade"

step "apt autoremove"
apt-get -o DPkg::Lock::Timeout=600 -y --purge autoremove || fail "apt autoremove"

# ── DietPi ────────────────────────────────────────────────────────────────────
# `1` is the non-interactive form: apply the update if there is one, no menu.
step "dietpi-update"
/boot/dietpi/dietpi-update 1 || fail "dietpi-update"

# ── Omnigent ──────────────────────────────────────────────────────────────────
# modules/30-omnigent.sh installs but never upgrades, on purpose — an hourly timer
# must not restart a server someone is using. Once a night, at 04:00, is when that
# becomes acceptable, and the restart only happens if the version actually moved.
if command -v /root/.local/bin/uv >/dev/null && command -v /root/.local/bin/omni >/dev/null; then
	before="$(/root/.local/bin/omni --version 2>/dev/null || echo unknown)"
	step "omnigent upgrade (at $before)"
	if /root/.local/bin/uv tool upgrade omnigent; then
		after="$(/root/.local/bin/omni --version 2>/dev/null || echo unknown)"
		if [[ $before != "$after" ]]; then
			echo "   $before -> $after, restarting"
			systemctl restart gilliserver-omnigent || fail "restarting gilliserver-omnigent"
		fi
	else
		fail "omnigent upgrade"
	fi
fi

# ── reboot ────────────────────────────────────────────────────────────────────
# Only when a package says one is needed — this is not the kiosk's unconditional
# nightly reboot, which is a thing we removed on purpose. In practice it means
# kernel and libc updates, which otherwise sit installed but not running.
if [[ ${#failed[@]} -gt 0 ]]; then
	echo "!! ${#failed[@]} step(s) failed: ${failed[*]}"
fi

if [[ -f /var/run/reboot-required ]]; then
	echo "=> reboot required, rebooting $(date -Is)"
	echo "=== update done $(date -Is) ==="
	systemctl reboot
	exit 0
fi

echo "=== update done $(date -Is) ==="
[[ ${#failed[@]} -eq 0 ]]
