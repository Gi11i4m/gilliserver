#!/bin/sh
# Run once per clone: git hooks are not cloned with a repo, so they have to be
# pointed at by hand. Without this, nothing stops a secret going public.
set -e
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
echo "pre-commit secret scan enabled (core.hooksPath=.githooks)"
