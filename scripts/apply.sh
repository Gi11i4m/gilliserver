#!/bin/bash
# The whole deployment, in one idempotent script. Runs at every boot and hourly
# after that (see config/etc/systemd/system/gilliserver-apply.timer).
#
#   1. pull the newest configuration from GitHub
#   2. copy everything under config/ onto the filesystem, path for path
#   3. run every module in modules/, in filename order
#
# Safe to run by hand at any time: `/opt/gilliserver/scripts/apply.sh`
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${GILLISERVER_BRANCH:-main}"
LOG=/root/.gilliserver-apply.log

# systemd gives a unit no HOME, and git aborts with "fatal: $HOME not set" the
# moment it wants a global config — which killed the entire boot-time apply while
# the hourly one from an ssh session kept working, so nothing looked wrong.
export HOME="${HOME:-/root}"

# git refuses to touch a repository owned by another user ("dubious ownership") and
# every git command in this script then fails — including the pull, so the box goes
# on applying stale config while looking like it succeeded. It happens the moment
# anything writes /opt/gilliserver as a non-root uid, which `setup/apply-now.sh
# --local` used to do. Only root runs this, and this path is ours.
git config --global --get-all safe.directory | grep -qx "$REPO_DIR" ||
	git config --global --add safe.directory "$REPO_DIR"

# Log to a file, not only to journald: DietPi keeps /var/log in RAM, so anything
# journald wrote about a run that ends in a reboot is gone before you can read it.
exec > >(tee -a "$LOG") 2>&1
echo "=== apply $(date -Is) ==="

# Where the boot partition is mounted. Older DietPi images put the FAT partition
# at /boot; the Bookworm RPi images moved it to /boot/firmware and left /boot on
# ext4. The secrets file has to sit on the FAT one — that is the only partition
# you can write from a laptop with the SD card in hand.
GILLISERVER_BOOT=/boot
if [[ "$(findmnt -n -o FSTYPE --target /boot/firmware 2>/dev/null)" == vfat ]]; then
	GILLISERVER_BOOT=/boot/firmware
fi

# An env file already sitting on the other one still wins, so a box set up before
# this check — or one whose /boot *is* the FAT partition — keeps working.
GILLISERVER_ENV="$GILLISERVER_BOOT/gilliserver.env"
if [[ ! -f $GILLISERVER_ENV ]]; then
	for candidate in /boot/firmware/gilliserver.env /boot/gilliserver.env; do
		[[ -f $candidate ]] && { GILLISERVER_ENV=$candidate; break; }
	done
fi
export GILLISERVER_BOOT GILLISERVER_ENV

if [[ -f $GILLISERVER_ENV ]]; then
	set -a; source "$GILLISERVER_ENV"; set +a
else
	echo "!! no $GILLISERVER_ENV — modules that need a secret will say so"
fi

# ── 1. pull ───────────────────────────────────────────────────────────────────
# Skipped with SKIP_PULL=1, which is what you want while testing a change you
# made on the box itself — otherwise the pull throws it away.
if [[ "${SKIP_PULL:-0}" != 1 ]]; then
	echo "-> pulling $BRANCH"
	# The repo is public, so this is normally unused — it is here so that making it
	# private is a matter of dropping a token in /boot/gilliserver.env, nothing more.
	if [[ -n "${GITHUB_TOKEN:-}" ]]; then
		git -C "$REPO_DIR" config credential.helper '!f() { echo "username=x-access-token"; echo "password=${GITHUB_TOKEN}"; }; f'
	fi
	git -C "$REPO_DIR" fetch --prune origin "$BRANCH" || echo "!! fetch failed, applying the config we already have"
	git -C "$REPO_DIR" reset --hard "origin/$BRANCH" || true
fi
echo "-> at $(git -C "$REPO_DIR" rev-parse --short HEAD) $(git -C "$REPO_DIR" log -1 --format=%s)"

# ── 2. deploy config/ ─────────────────────────────────────────────────────────
# config/ mirrors the filesystem: config/etc/foo/bar lands at /etc/foo/bar.
echo "-> deploying config/"
changed_units=0
while IFS= read -r -d '' src; do
	dest="/${src#"$REPO_DIR/config/"}"
	mkdir -p "$(dirname "$dest")"
	if ! cmp -s "$src" "$dest"; then
		install -m "$(stat -c %a "$src")" "$src" "$dest"
		echo "   ~ $dest"
		if [[ $dest == /etc/systemd/system/* ]]; then changed_units=1; fi
	fi
done < <(find "$REPO_DIR/config" -type f -print0)

if [[ $changed_units == 1 ]]; then
	systemctl daemon-reload
fi

# Units are enabled from the repo, not by hand, so a reflash brings them back.
while IFS= read -r unit; do
	systemctl is-enabled "$unit" &>/dev/null || { echo "   + enabling $unit"; systemctl enable "$unit"; }

	# `enable` only writes the symlink — it does not start anything. A timer stayed
	# dormant until the next reboot, so the whole point of the hourly re-apply was
	# missing for however long the box happened to stay up. Services are left alone
	# on purpose: apply.sh restarting a service mid-run is how you lose a box, and
	# that is each module's job for the units it owns.
	if [[ $unit == *.timer ]]; then
		systemctl is-active "$unit" &>/dev/null || { echo "   + starting $unit"; systemctl start "$unit"; }
	fi
done < <(grep -rl '^\[Install\]' "$REPO_DIR/config/etc/systemd/system" | xargs -r -n1 basename)

# ── 3. run modules ────────────────────────────────────────────────────────────
# One file per concern, run in filename order. Each must be idempotent: it runs
# again on every boot and every hour. Disable one with MODULES_SKIP="30-omnigent".
for module in "$REPO_DIR"/modules/*.sh; do
	name="$(basename "$module" .sh)"
	if [[ " ${MODULES_SKIP:-} " == *" $name "* ]]; then
		echo "-> skipping module $name"
		continue
	fi
	echo "-> module $name"
	bash "$module" || echo "!! module $name failed (continuing)"
done

echo "=== apply done $(date -Is) ==="
