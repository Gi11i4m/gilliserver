#!/bin/bash
# Installs the Omnigent CLI (omnigent.ai). Running it as a service is the next step
# and has no unit in config/ yet — see "What is not done yet" in the README.
#
# NOT YET VERIFIED ON HARDWARE. Omnigent wants Python 3.12+, Node 22 and tmux, and
# a Pi 3 B has 1 GB of RAM and no swap by default — expect to need a swapfile, and
# expect the first install to take the better part of an hour. Whoever runs this on
# the real box first: fix what is wrong here and commit it, do not patch it live.
set -euo pipefail

if ! command -v omni >/dev/null; then
	curl -fsSL https://omnigent.ai/install.sh | sh
fi

omni --version || echo "!! omni installed but not on PATH for this shell"
