#!/usr/bin/env bash
# install.sh — drop session-digest.sh and the /recap slash command into ~/.claude
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/commands"

cp "$REPO/session-digest.sh" "$HOME/.claude/scripts/session-digest.sh"
chmod +x "$HOME/.claude/scripts/session-digest.sh"

cp "$REPO/commands/recap.md" "$HOME/.claude/commands/recap.md"

cat <<MSG
Installed:
  $HOME/.claude/scripts/session-digest.sh
  $HOME/.claude/commands/recap.md

Try it:
  ~/.claude/scripts/session-digest.sh yesterday   # plain list
  # …or inside any Claude Code session:
  /recap yesterday
MSG
