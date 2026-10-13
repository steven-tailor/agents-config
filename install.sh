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

# --- UI ----------------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  TTY=1 B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' X=$'\e[0m'
else
  TTY=0 B='' D='' G='' Y='' C='' X=''
fi

STEP=0
TOTAL=0

tilde() { echo "${1/#$HOME/~}"; }

# Progress bar on the last terminal line, redrawn after every message.
bar() {
  (( TTY && TOTAL )) || return 0
  local width=28 done_w filled empty
  done_w=$(( STEP * width / TOTAL ))
  printf -v filled '%*s' "$done_w" ''
  printf -v empty '%*s' "$(( width - done_w ))" ''
  printf '\r\e[K  %s%s%s%s%s %s%d/%d%s' \
    "$C" "${filled// /█}" "$D" "${empty// /░}" "$X" "$D" "$STEP" "$TOTAL" "$X"
}

say() {
  (( TTY )) && printf '\r\e[K'
  printf '%s\n' "$*"
  bar
}

# item <icon> <color> <label> [detail]
item() { say "  $2$1$X $(printf '%-17s' "$3") $D${4:-}$X"; }

tick() { STEP=$(( STEP + 1 )); bar; }

# --- Bootstrap ---------------------------------------------------------------

# Piped from curl there is no repo next to the script: clone or update it into
# INSTALL_DIR and re-run from there, since the symlinks point into the clone.
SELF="${BASH_SOURCE[0]:-}"
if [[ -z "$SELF" || ! -f "$SELF" || ! -d "$(dirname "$SELF")/agents" ]]; then
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    item "⇣" "$C" "Updating" "$(tilde "$INSTALL_DIR")"
    git -C "$INSTALL_DIR" pull --ff-only --quiet
  else
    item "⇣" "$C" "Cloning" "$(tilde "$INSTALL_DIR")"
    git clone --quiet "$REPO_URL" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/install.sh" "$@"
fi

# --- Install -----------------------------------------------------------------

REPO="$(cd "$(dirname "$SELF")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
LINKED=0 RELINKED=0 BACKED_UP=0 UP_TO_DATE=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# <repo path>:<name in tool config dir>
CLAUDE_LINKS=("build/claude/agents:agents" "skills:skills")
CODEX_LINKS=(
  "Codex/AGENTS.md:AGENTS.md"
  "build/codex/agents:agents"
  "Codex/keybindings.json:keybindings.json"
  "skills:skills"
)

run() { (( DRY_RUN )) || "$@"; }

# link <source in repo> <target path>
link() {
  local src="$REPO/$1" dst="$2" name="${2##*/}"

  if [[ ! -e "$src" ]]; then
    item "–" "$Y" "$name" "missing in repo"
  elif [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    item "✓" "$G" "$name" "up to date"
    UP_TO_DATE=$(( UP_TO_DATE + 1 ))
  elif [[ -L "$dst" ]]; then
    run rm "$dst"
    run ln -s "$src" "$dst"
    item "↻" "$C" "$name" "relinked"
    RELINKED=$(( RELINKED + 1 ))
  elif [[ -e "$dst" ]]; then
    run mv "$dst" "$dst.backup-$STAMP"
    run ln -s "$src" "$dst"
    item "⤓" "$Y" "$name" "backed up → $name.backup-$STAMP"
    BACKED_UP=$(( BACKED_UP + 1 ))
  else
    run ln -s "$src" "$dst"
    item "+" "$G" "$name" "linked"
    LINKED=$(( LINKED + 1 ))
  fi
  tick
}

# A tool counts as installed when its config dir or CLI exists.
found() { [[ -d "$2" ]] || command -v "$1" >/dev/null; }

# install_tool <target> <label> <config dir> <links...>
install_tool() {
  local target="$1" label="$2" dir="$3" pair count
  shift 3

  say ""
  say "  $B$label$X  $D$(tilde "$dir")$X"
  run mkdir -p "$dir"
  python3 "$REPO/scripts/build_agents.py" --target "$target" >/dev/null
  count=$(find "$REPO/build/$target/agents" -type f | wc -l | tr -d ' ')
  item "⚙" "$G" "build agents" "$count generated"
  tick

  for pair in "$@"; do
    link "${pair%%:*}" "$dir/${pair#*:}"
  done
}

say ""
say "  ${B}agents-config$X$( (( DRY_RUN )) && echo "  ${Y}dry run · nothing changes$X")"
say ""

HAS_CLAUDE=0 HAS_CODEX=0
if found claude "$CLAUDE_DIR"; then
  HAS_CLAUDE=1 TOTAL=$(( TOTAL + 1 + ${#CLAUDE_LINKS[@]} ))
  item "●" "$G" "Claude Code" "found"
else
  item "○" "$D" "Claude Code" "not found · skip"
fi
if found codex "$CODEX_DIR"; then
  HAS_CODEX=1 TOTAL=$(( TOTAL + 1 + ${#CODEX_LINKS[@]} ))
  item "●" "$G" "Codex" "found"
else
  item "○" "$D" "Codex" "not found · skip"
fi

if (( TOTAL == 0 )); then
  say ""
  say "  ${Y}Nothing to install: neither Claude Code nor Codex found.$X"
  exit 1
fi

(( HAS_CLAUDE )) && install_tool claude "Claude Code" "$CLAUDE_DIR" "${CLAUDE_LINKS[@]}"
(( HAS_CODEX )) && install_tool codex "Codex" "$CODEX_DIR" "${CODEX_LINKS[@]}"

summary=""
for part in "$LINKED linked" "$RELINKED relinked" "$BACKED_UP backed up" "$UP_TO_DATE up to date"; do
  [[ "$part" == 0\ * ]] || summary+="${summary:+ · }$part"
done
# Keep the finished bar on screen and stop redrawing it.
(( TTY )) && printf '\n'
TOTAL=0
say ""
if (( DRY_RUN )); then
  say "  ${Y}✓ Dry run$X  $D$summary$X"
else
  say "  ${G}✓ Done$X  $D$summary$X"
fi
say ""
