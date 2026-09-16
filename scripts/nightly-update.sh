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
#
# Only tee when there is someone watching. Under systemd, `tee` from a process
# substitution lives in the service's cgroup and gets killed the moment the main
# process exits, which truncated the end of every unattended run — the first run of
# this script logged its whole apt upgrade and then lost the line saying it had
# finished. Appending straight to the file has no second process to lose.
if [[ -t 1 ]]; then
	exec > >(tee -a "$LOG") 2>&1
else
	exec >> "$LOG" 2>&1
fi
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

# /var/run/reboot-required is an Ubuntu/needrestart convention. Nothing on this box
# writes it: Raspberry Pi's kernel packages do not, and needrestart is not
# installed — so the first real run installed kernel 6.12.109, kept running
# 6.12.96, and reported that no reboot was needed. Checked anyway, in case
# needrestart ever arrives, but the kernel comparison is what actually fires here.
newest_kernel="$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%f\n' 2>/dev/null |
	sed 's/^vmlinuz-//' | sort -V | tail -1)"
running_kernel="$(uname -r)"

if [[ -f /var/run/reboot-required ]]; then
	reboot_reason="a package asked for it"
elif [[ -n $newest_kernel && $newest_kernel != "$running_kernel" ]]; then
	reboot_reason="kernel $running_kernel -> $newest_kernel"
fi

if [[ -n ${reboot_reason:-} ]]; then
	echo "=> rebooting: $reboot_reason"
	echo "=== update done $(date -Is) ==="
	systemctl reboot
	exit 0
fi

echo "=== update done $(date -Is) ==="
[[ ${#failed[@]} -eq 0 ]]
