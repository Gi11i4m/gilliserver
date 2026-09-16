#!/bin/bash
# Refuses to let a secret into this repo. It is public: anything committed here is
# public the moment it is pushed, and rewriting history does not un-leak it.
#
#   scripts/check-secrets.sh          # what is staged right now (used by the git hook)
#   scripts/check-secrets.sh --all    # every tracked file (used by CI)
#
# Exits non-zero on a hit. Secrets belong in /boot/gilliserver.env on the device.
set -uo pipefail

MODE="${1:-staged}"
found=0

# Files that must never be committed at all, whatever is in them.
FORBIDDEN_NAMES='(^|/)(gilliserver\.env|secrets?\.env|\.env|.*\.pem|.*\.key|id_[a-z]+|.*\.p12)$'

# Known-shape credentials: a hit here is a real secret, not a guess.
PATTERNS=(
	'tskey-[A-Za-z0-9-]{8,}'                 # Tailscale auth key
	'gh[pousr]_[A-Za-z0-9]{16,}'             # GitHub token
	'github_pat_[A-Za-z0-9_]{20,}'           # GitHub fine-grained PAT
	'sk-ant-[A-Za-z0-9_-]{16,}'              # Anthropic API key
	'sk-[A-Za-z0-9]{32,}'                    # OpenAI-style key
	'AKIA[0-9A-Z]{16}'                       # AWS access key id
	'AIza[0-9A-Za-z_-]{30,}'                 # Google API key
	'-----BEGIN [A-Z ]*PRIVATE KEY-----'     # any private key
	'xox[baprs]-[A-Za-z0-9-]{10,}'           # Slack token
)

# A secret-shaped variable with an actual value in it. `FOO=`, `FOO=$BAR` and
# `FOO="${BAR}"` are fine — those are the placeholders and the reads, not the value.
# Case-insensitive on purpose: a lowercase `wifi_password` assignment is as much of
# a leak as an uppercase one. (Yes, this scanner flags its own examples — that is why
# this comment describes them instead of spelling them out.)
ASSIGNMENT='(TOKEN|SECRET|PASSWORD|PASSWD|AUTHKEY|AUTH_KEY|API_KEY|APIKEY|ACCESS_KEY|PRIVATE_KEY)[A-Z_]*[[:space:]]*=[[:space:]]*"?'"'"'?[^"'"'"'$[:space:]]'

report() { echo "  $1"; found=1; }

if [[ $MODE == --all ]]; then
	files=$(git ls-files)
	content=$(git grep -nI '' -- $(git ls-files) 2>/dev/null)
else
	files=$(git diff --cached --name-only --diff-filter=ACM)
	# Only added lines: an existing false positive should not block every commit.
	content=$(git diff --cached -U0 --diff-filter=ACM | grep '^+' | grep -v '^+++')
fi

for f in $files; do
	if [[ $f =~ $FORBIDDEN_NAMES ]] && [[ $f != *.example ]]; then
		report "$f — this file holds secrets and must not be committed"
	fi
done

for pattern in "${PATTERNS[@]}"; do
	hits=$(grep -nEI -e "$pattern" <<< "$content" | grep -v 'check-secrets' || true)
	[[ -n $hits ]] && report "looks like a credential: $(head -1 <<< "$hits" | cut -c1-120)"
done

hits=$(grep -niEI -e "$ASSIGNMENT" <<< "$content" | grep -vE 'check-secrets|EXAMPLE|example|<your|\.\.\.' || true)
[[ -n $hits ]] && while IFS= read -r line; do
	report "a secret-shaped variable has a value: $(cut -c1-120 <<< "$line")"
done <<< "$hits"

if [[ $found == 1 ]]; then
	cat <<'MSG'

REFUSED: this repo is public and the above looks like a secret.

Secrets live in /boot/gilliserver.env on the device — see AGENTS.md. Add the name
(never a value) to boot/gilliserver.env.example if it is a new one.

If this is genuinely a false positive, commit with --no-verify and say so out loud.
MSG
	exit 1
fi

echo "no secrets found ($MODE)"
