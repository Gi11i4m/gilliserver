#!/bin/bash
# Make gilliserver pick up what you just pushed, instead of waiting for the timer.
#
#   setup/apply-now.sh              # pull main and apply
#   setup/apply-now.sh --local      # rsync the working tree first, for testing
set -euo pipefail

HOST="${GILLISERVER_HOST:-gilliserver}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == --local ]]; then
	# Deliberately not the normal path: the box is supposed to build itself from
	# git. This is for trying something out before you commit it, and the next
	# scheduled apply will pull it straight back out again.
	echo "-> rsyncing working tree to $HOST (will be overwritten on the next pull)"
	# --no-o --no-g: plain `-a` copies your laptop's uid/gid onto the Pi, which
	# leaves /opt/gilliserver owned by a user that does not exist there. git then
	# refuses the repo as "dubious ownership" and every later pull fails silently.
	rsync -a --no-o --no-g --delete --exclude .git "$REPO_DIR/" "root@$HOST:/opt/gilliserver/"
	ssh "root@$HOST" "SKIP_PULL=1 /opt/gilliserver/scripts/apply.sh"
else
	ssh "root@$HOST" "/opt/gilliserver/scripts/apply.sh"
fi
