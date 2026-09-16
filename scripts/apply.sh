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

# Log to a file, not only to journald: DietPi keeps /var/log in RAM, so anything
# journald wrote about a run that ends in a reboot is gone before you can read it.
exec > >(tee -a "$LOG") 2>&1
echo "=== apply $(date -Is) ==="

if [[ -f /boot/gilliserver.env ]]; then
	set -a; source /boot/gilliserver.env; set +a
fi

# ── 1. pull ───────────────────────────────────────────────────────────────────
# Skipped with SKIP_PULL=1, which is what you want while testing a change you
# made on the box itself — otherwise the pull throws it away.
if [[ "${SKIP_PULL:-0}" != 1 ]]; then
	echo "-> pulling $BRANCH"
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
