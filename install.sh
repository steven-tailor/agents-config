#!/usr/bin/env bash
# Build agents for each installed tool (Claude Code, Codex) from agents/ and
# symlink them, plus shared skills and Codex configs, into the tool config dirs.
# Re-run after editing agents/ to regenerate.
# Idempotent: existing symlinks are repointed, real files/dirs are backed up
# as <name>.backup-<timestamp> before linking.
#
# Usage: ./install.sh [--dry-run]
#        curl -fsSL <raw install.sh URL> | bash [-s -- --dry-run]

set -euo pipefail

REPO_URL="${AGENTS_CONFIG_REPO:-https://github.com/steven-tailor/agents-config.git}"
INSTALL_DIR="${AGENTS_CONFIG_DIR:-$HOME/.agents-config}"

# Piped from curl there is no repo next to the script: clone or update it into
# INSTALL_DIR and re-run from there, since the symlinks point into the clone.
SELF="${BASH_SOURCE[0]:-}"
if [[ -z "$SELF" || ! -f "$SELF" || ! -d "$(dirname "$SELF")/agents" ]]; then
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating $INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only --quiet
  else
    echo "Cloning $REPO_URL into $INSTALL_DIR"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/install.sh" "$@"
fi

REPO="$(cd "$(dirname "$SELF")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

run() {
  if (( DRY_RUN )); then echo "  [dry-run] $*"; else "$@"; fi
}

# link <source in repo> <target path>
link() {
  local src="$REPO/$1" dst="$2"

  if [[ ! -e "$src" ]]; then
    echo "  skip  $dst (missing $1 in repo)"
    return
  fi

  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    echo "  ok    $dst"
    return
  fi

  if [[ -L "$dst" ]]; then
    echo "  relink $dst (was -> $(readlink "$dst"))"
    run rm "$dst"
  elif [[ -e "$dst" ]]; then
    echo "  backup $dst -> $dst.backup-$STAMP"
    run mv "$dst" "$dst.backup-$STAMP"
  else
    echo "  link  $dst"
  fi

  run ln -s "$src" "$dst"
}

# install_tool <target> <cli command> <config dir> <repo path>:<target name>...
# A tool counts as installed when its config dir or CLI exists.
install_tool() {
  local target="$1" cmd="$2" dir="$3"
  shift 3

  if [[ ! -d "$dir" ]] && ! command -v "$cmd" >/dev/null; then
    echo "$target: not installed, skipping"
    return
  fi

  echo "$target: $dir"
  run mkdir -p "$dir"
  python3 "$REPO/scripts/build_agents.py" --target "$target"

  local pair
  for pair in "$@"; do
    link "${pair%%:*}" "$dir/${pair#*:}"
  done
}

install_tool claude claude "$CLAUDE_DIR" \
  "build/claude/agents:agents" \
  "skills:skills"

install_tool codex codex "$CODEX_DIR" \
  "Codex/AGENTS.md:AGENTS.md" \
  "build/codex/agents:agents" \
  "Codex/keybindings.json:keybindings.json" \
  "skills:skills"
