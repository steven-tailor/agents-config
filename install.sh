#!/usr/bin/env bash
# Build agents for each installed tool (Claude Code, Codex) from agents/ and
# symlink them, plus shared skills and global instructions, into the tool config
# dirs. Fetches the skills in skills.toml, installs the plugins in plugins.toml
# and adds the MCP servers in mcp.toml.
# Re-run after editing agents/ to regenerate.
#
# Never destroys anything the tools or the user created:
# - agents/ and skills/ in the tool config dirs are real folders holding one
#   symlink per managed entry, so anything else in them is left alone;
# - real files and folders in the way are renamed to <name>.backup-<timestamp>;
# - generated agents changed outside the repo are kept, not overwritten;
# - updates are skipped when the clone has local changes.
#
# Usage: ./install.sh [--dry-run] [--force] [--update] [--no-auto-update] [--help]
#        curl -fsSL <raw install.sh URL> | bash [-s -- <options>]
# --help, -h        print this usage and exit
# --force           overwrite generated agents and external skills changed outside the repo
# --update          pull the latest version of the clone before installing
# --no-auto-update  remove the daily `install.sh --update` job (installed by default)

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

# --- Options -----------------------------------------------------------------

DRY_RUN=0 UPDATE=0 AUTO_UPDATE=1
FORCE=()
PASS=()  # options for the re-run after an update

# usage: print the Usage block of the header comment. Piped from curl the script
# is not a file, so there is no header to read.
usage() {
  local self="${BASH_SOURCE[0]:-}"
  if [[ -f "$self" ]]; then
    sed -n '/^# Usage:/,/^$/{/^$/q;s/^# \{0,1\}//p;}' "$self"
  else
    echo "Usage: install.sh [options]; download install.sh to see the option list"
  fi
}

for arg in "$@"; do
  case "$arg" in
    --help|-h) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=(--force) ;;
    --update) UPDATE=1; continue ;;
    --no-auto-update) AUTO_UPDATE=0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
  PASS+=("$arg")
done

# --- Bootstrap ---------------------------------------------------------------

# shallow_update <clone> <branch>: move a shallow clone to the latest commit
# and drop everything older, so only the current version is stored.
# `git checkout` refuses to overwrite untracked files, so nothing is lost.
shallow_update() {
  local git=(git -C "$1") before remote
  before="$("${git[@]}" rev-parse HEAD)"
  remote="$("${git[@]}" rev-parse "origin/$2")"
  "${git[@]}" fetch --quiet --depth 1 origin "$2" || return 1
  if ! "${git[@]}" checkout --quiet -B "$2" FETCH_HEAD 2>/dev/null; then
    # Keep origin/<branch> at HEAD, or the next run sees HEAD as a local commit.
    "${git[@]}" update-ref "refs/remotes/origin/$2" "$remote"
    return 1
  fi
  if [[ "$("${git[@]}" rev-parse HEAD)" != "$before" ]]; then
    "${git[@]}" reflog expire --expire=now --all
    "${git[@]}" gc --quiet --prune=now
  fi
}

# update_repo <clone>: update it unless that could lose local changes.
# Shallow clones made by this script keep only the latest commit; full clones
# (e.g. a development checkout) get a plain fast-forward and keep history.
update_repo() {
  local git=(git -C "$1") branch ok=0
  branch="$("${git[@]}" symbolic-ref --quiet --short HEAD || true)"

  if [[ -z "$branch" ]]; then
    item "⚠" "$Y" "Update skipped" "no branch checked out in $(tilde "$1")"
    return
  elif [[ -n "$("${git[@]}" status --porcelain --untracked-files=no)" ]]; then
    item "⚠" "$Y" "Update skipped" "local changes in $(tilde "$1")"
    return
  elif [[ -n "$("${git[@]}" rev-list "origin/$branch..HEAD" 2>/dev/null)" ]]; then
    item "⚠" "$Y" "Update skipped" "local commits in $(tilde "$1")"
    return
  fi

  if [[ "$("${git[@]}" rev-parse --is-shallow-repository)" == true ]]; then
    shallow_update "$1" "$branch" && ok=1
  else
    "${git[@]}" pull --ff-only --quiet 2>/dev/null && ok=1
  fi

  if (( ok )); then
    item "⇣" "$C" "Updated" "$(tilde "$1") · $("${git[@]}" log -1 --format=%h)"
  else
    item "⚠" "$Y" "Update failed" "keeping current version"
  fi
}

# Piped from curl there is no repo next to the script: clone or update it into
# INSTALL_DIR and re-run from there, since the symlinks point into the clone.
# With --update, pull the clone the script lives in and re-run the new version.
SELF="${BASH_SOURCE[0]:-}"
if [[ -z "$SELF" || ! -f "$SELF" || ! -d "$(dirname "$SELF")/agents" ]]; then
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    update_repo "$INSTALL_DIR"
  else
    item "⇣" "$C" "Cloning" "$(tilde "$INSTALL_DIR")"
    # Shallow: users get only the latest version; see update_repo.
    git clone --quiet --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi
  exec bash "$INSTALL_DIR/install.sh" "${PASS[@]+"${PASS[@]}"}"
elif (( UPDATE )); then
  [[ -t 1 ]] || echo "--- $(date '+%Y-%m-%d %H:%M:%S')"
  update_repo "$(cd "$(dirname "$SELF")" && pwd)"
  exec bash "$SELF" "${PASS[@]+"${PASS[@]}"}"
fi

# --- Install -----------------------------------------------------------------

REPO="$(cd "$(dirname "$SELF")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LINKED=0 RELINKED=0 BACKED_UP=0 UP_TO_DATE=0 WARNINGS=0

# <repo path>:<name in tool config dir>[:entry to never carry over]. A trailing
# / links every entry of the folder into a real folder instead of linking the
# folder itself. skills/synced is Claude's and skills/.system is Codex's.
# build/external/skills holds the skills listed in skills.toml.
CLAUDE_LINKS=(
  "global/AGENTS.md:CLAUDE.md"
  "build/claude/agents/:agents"
  "skills/:skills:.system"
  "build/external/skills/:skills"
)
CODEX_LINKS=(
  "global/AGENTS.md:AGENTS.md"
  "build/codex/agents/:agents"
  "skills/:skills:synced"
  "build/external/skills/:skills"
)

run() { (( DRY_RUN )) || "$@"; }

# link_one <source> <target>: link and set RESULT to what happened.
link_one() {
  local src="$1" dst="$2"

  if [[ ! -e "$src" ]]; then
    RESULT=missing
  elif [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    RESULT=ok
    UP_TO_DATE=$(( UP_TO_DATE + 1 ))
  elif [[ -L "$dst" ]]; then
    run rm "$dst"
    run ln -s "$src" "$dst"
    RESULT=relinked
    RELINKED=$(( RELINKED + 1 ))
  elif [[ -e "$dst" ]]; then
    run mv "$dst" "$dst.backup-$STAMP"
    run ln -s "$src" "$dst"
    RESULT=backup
    BACKED_UP=$(( BACKED_UP + 1 ))
  else
    run ln -s "$src" "$dst"
    RESULT=linked
    LINKED=$(( LINKED + 1 ))
  fi
}

# link_file <source in repo> <target path>
link_file() {
  local name="${2##*/}"
  link_one "$REPO/$1" "$2"
  case "$RESULT" in
    missing)  item "–" "$Y" "$name" "missing in repo" ;;
    ok)       item "✓" "$G" "$name" "up to date" ;;
    relinked) item "↻" "$C" "$name" "relinked" ;;
    backup)   item "⤓" "$Y" "$name" "backed up → $name.backup-$STAMP" ;;
    linked)   item "+" "$G" "$name" "linked" ;;
  esac
  tick
}

# link_dir <source folder in repo> <target folder>
# Links each entry of the source folder into a real target folder. Entries the
# tool or the user put there are left untouched.
# managed_entries <source folder>: names this repo owns in that folder. Agents
# come from the build manifest, everything else from git, so files the tools
# wrote into the clone are never mistaken for ours.
managed_entries() {
  local src="$1"
  if [[ -f "${src%/*}/manifest.json" ]]; then
    python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))))' "${src%/*}/manifest.json"
  else
    git -C "$REPO" ls-files -- "${src#"$REPO"/}" | sed "s|^${src#"$REPO"/}/||; s|/.*||" | sort -u
  fi
}

# link_dir <source folder in repo> <target folder> [entry to never carry over]
# Links each entry of the source folder into a real target folder. Entries the
# tool or the user put there are left untouched.
link_dir() {
  local src="$REPO/${1%/}" dst="$2" skip="${3:-}" name="${2##*/}/" entry base old
  [[ "$1" == build/external/* ]] && name="external $name"
  local new=0 copied=0 backups=0 removed=0 own=0 total=0
  local managed=()

  while IFS= read -r base; do
    [[ -n "$base" && -e "$src/$base" ]] && managed+=("$base")
  done < <(managed_entries "$src")
  is_managed() { local m; for m in "${managed[@]+"${managed[@]}"}"; do [[ "$m" == "$1" ]] && return 0; done; return 1; }

  # Older installs linked the whole folder, possibly shared by both tools.
  # Turn it into a real folder and copy over whatever the tools wrote through
  # that link; the originals stay where they are.
  if [[ -L "$dst" ]]; then
    old="$(cd "$dst" 2>/dev/null && pwd -P || true)"
    run rm "$dst"
    run mkdir -p "$dst"
    if [[ -n "$old" ]]; then
      for entry in "$old"/* "$old"/.[!.]*; do
        [[ -e "$entry" ]] || continue
        base="${entry##*/}"
        is_managed "$base" && continue
        [[ "$base" == .DS_Store || "$base" == "$skip" ]] && continue
        run cp -R "$entry" "$dst/"
        copied=$(( copied + 1 ))
      done
    fi
  elif [[ -e "$dst" && ! -d "$dst" ]]; then
    run mv "$dst" "$dst.backup-$STAMP"
    BACKED_UP=$(( BACKED_UP + 1 ))
    run mkdir -p "$dst"
  else
    run mkdir -p "$dst"
  fi

  for base in "${managed[@]+"${managed[@]}"}"; do
    link_one "$src/$base" "$dst/$base"
    total=$(( total + 1 ))
    case "$RESULT" in
      relinked|linked) new=$(( new + 1 )) ;;
      backup) backups=$(( backups + 1 )) ;;
    esac
  done

  # Drop links to entries that were removed from the repo; count the rest.
  for entry in "$dst"/* "$dst"/.[!.]*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    base="${entry##*/}"
    is_managed "$base" && continue
    if [[ -L "$entry" && "$(readlink "$entry")" == "$REPO"/* && ! -e "$entry" ]]; then
      run rm "$entry"
      removed=$(( removed + 1 ))
    elif [[ "$base" != .DS_Store && ! ( -L "$entry" && "$(readlink "$entry")" == "$REPO"/* ) ]]; then
      own=$(( own + 1 ))
    fi
  done

  local detail="$total linked"
  (( new )) && detail+=" · $new new"
  (( backups )) && detail+=" · $backups backed up"
  (( removed )) && detail+=" · $removed removed"
  (( copied )) && detail+=" · $copied carried over"
  (( own )) && detail+=" · $own yours untouched"
  item "✓" "$G" "$name" "$detail"
  tick
}

# --- Auto-update ---------------------------------------------------------------

JOB_LABEL="agents-config.update"
JOB_HOUR=12
JOB_LOG="$REPO/build/auto-update.log"
JOB_PLIST="$HOME/Library/LaunchAgents/$JOB_LABEL.plist"

xml_escape() { local s="${1//&/&amp;}"; s="${s//</&lt;}"; echo "${s//>/&gt;}"; }

launchd_plist() {
  local env="" var
  # launchd starts with a bare PATH; keep this shell's so python3, git and the
  # tool CLIs resolve, plus any config dir overrides.
  for var in PATH CLAUDE_CONFIG_DIR CODEX_HOME; do
    [[ -n "${!var:-}" ]] && env+="    <key>$var</key><string>$(xml_escape "${!var}")</string>"$'\n'
  done
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$JOB_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$(xml_escape "$REPO/install.sh")</string>
    <string>--update</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
${env}  </dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>$JOB_HOUR</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$(xml_escape "$JOB_LOG")</string>
  <key>StandardErrorPath</key><string>$(xml_escape "$JOB_LOG")</string>
</dict>
</plist>
PLIST
}

cron_line() {
  printf '0 %d * * * PATH=%q %q %q --update >> %q 2>&1 # %s\n' \
    "$JOB_HOUR" "$PATH" /bin/bash "$REPO/install.sh" "$JOB_LOG" "$JOB_LABEL"
}

# Register, refresh or remove the daily `install.sh --update` job.
auto_update() {
  local current wanted
  if [[ "$(uname)" == Darwin ]]; then
    if (( ! AUTO_UPDATE )); then
      if [[ -f "$JOB_PLIST" ]]; then
        run launchctl bootout "gui/$(id -u)" "$JOB_PLIST" 2>/dev/null || true
        run rm "$JOB_PLIST"
        item "–" "$Y" "auto-update" "removed"
      else
        item "○" "$D" "auto-update" "off"
      fi
      return
    fi
    wanted="$(launchd_plist)"
    current="$(cat "$JOB_PLIST" 2>/dev/null || true)"
    if [[ "$current" == "$wanted" ]]; then
      item "✓" "$G" "auto-update" "daily $JOB_HOUR:00 · launchd"
      return
    fi
    if (( ! DRY_RUN )); then
      mkdir -p "${JOB_PLIST%/*}" "${JOB_LOG%/*}"
      printf '%s\n' "$wanted" > "$JOB_PLIST"
      launchctl bootout "gui/$(id -u)" "$JOB_PLIST" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$JOB_PLIST"
    fi
    item "⏱" "$G" "auto-update" "daily $JOB_HOUR:00 · launchd · log $(tilde "$JOB_LOG")"
  elif command -v crontab >/dev/null; then
    current="$(crontab -l 2>/dev/null || true)"
    local others
    others="$(grep -v "# $JOB_LABEL\$" <<< "$current" || true)"
    if (( ! AUTO_UPDATE )); then
      if [[ "$current" != "$others" ]]; then
        (( DRY_RUN )) || printf '%s\n' "$others" | crontab -
        item "–" "$Y" "auto-update" "removed"
      else
        item "○" "$D" "auto-update" "off"
      fi
      return
    fi
    wanted="$(cron_line)"
    if grep -qxF "$wanted" <<< "$current"; then
      item "✓" "$G" "auto-update" "daily $JOB_HOUR:00 · cron"
      return
    fi
    if (( ! DRY_RUN )); then
      mkdir -p "${JOB_LOG%/*}"
      printf '%s\n%s\n' "$others" "$wanted" | sed '/^$/d' | crontab -
    fi
    item "⏱" "$G" "auto-update" "daily $JOB_HOUR:00 · cron · log $(tilde "$JOB_LOG")"
  else
    item "○" "$D" "auto-update" "no launchd or cron · skip"
  fi
}

# Fetch the skills listed in skills.toml into build/external/skills, shared by
# both tools. A failed fetch keeps the previous copy.
fetch_skills() {
  local line count=0 total=0
  say ""
  while IFS= read -r line; do
    case "$line" in
      kept\ *)
        item "⚠" "$Y" "${line#kept }" "edited outside repo · kept (--force to overwrite)"
        WARNINGS=$(( WARNINGS + 1 )) ;;
      failed\ *)
        line="${line#failed }"
        item "⚠" "$Y" "${line%%: *}" "fetch failed · ${line#*: }"
        WARNINGS=$(( WARNINGS + 1 )) ;;
      */*\ external\ skills\ *)
        count="${line%%/*}" total="${line#*/}" total="${total%% *}" ;;
    esac
  done < <(python3 "$REPO/scripts/fetch_skills.py" "${FORCE[@]+"${FORCE[@]}"}")
  item "⇣" "$G" "fetch skills" "$count/$total from skills.toml"
  tick
}

# install_plugins <tool> <skills dirs...>: install the plugins in plugins.toml
# through the tool's CLI, unless already installed in any way.
install_plugins() {
  local tool="$1" line name args=() dry=()
  shift
  for line in "$@"; do args+=(--skills-dir "$line"); done
  (( DRY_RUN )) && dry=(--dry-run)
  while IFS= read -r line; do
    name="${line#* }" name="${name%%:*}"
    case "$line" in
      installed\ *)
        if (( DRY_RUN )); then item "+" "$G" "$name" "plugin · would install"
        else item "+" "$G" "$name" "plugin · installed"; fi ;;
      present\ *:*) item "✓" "$G" "$name" "${line#*: }" ;;
      present\ *) item "✓" "$G" "$name" "plugin · installed" ;;
      skipped\ *) item "○" "$D" "$name" "plugin · ${line#*: }" ;;
      failed\ *)
        item "⚠" "$Y" "$name" "plugin · ${line#*: }"
        WARNINGS=$(( WARNINGS + 1 )) ;;
    esac
  done < <(python3 "$REPO/scripts/install_plugins.py" --tool "$tool" \
    "${args[@]+"${args[@]}"}" "${dry[@]+"${dry[@]}"}")
  tick
}

# install_mcp <tool>: add the MCP servers in mcp.toml, unless already there.
install_mcp() {
  local tool="$1" line name dry=()
  (( DRY_RUN )) && dry=(--dry-run)
  while IFS= read -r line; do
    name="${line#* }" name="${name%%:*}"
    case "$line" in
      installed\ *)
        if (( DRY_RUN )); then item "+" "$G" "$name" "MCP · would add"
        else item "+" "$G" "$name" "MCP · added"; fi ;;
      present\ *) item "✓" "$G" "$name" "MCP · present" ;;
      skipped\ *) item "○" "$D" "$name" "MCP · ${line#*: }" ;;
      failed\ *)
        item "⚠" "$Y" "$name" "MCP · ${line#*: }"
        WARNINGS=$(( WARNINGS + 1 )) ;;
    esac
  done < <(python3 "$REPO/scripts/install_mcp.py" --tool "$tool" "${dry[@]+"${dry[@]}"}")
  tick
}

# A tool counts as installed when its config dir or CLI exists.
found() { [[ -d "$2" ]] || command -v "$1" >/dev/null; }

# install_tool <target> <label> <config dir> <links...>
install_tool() {
  local target="$1" label="$2" dir="$3" pair line count kept=()
  shift 3

  say ""
  say "  $B$label$X  $D$(tilde "$dir")$X"
  run mkdir -p "$dir"

  while IFS= read -r line; do
    [[ "$line" == kept\ * ]] && kept+=("${line#kept }")
  done < <(python3 "$REPO/scripts/build_agents.py" --target "$target" "${FORCE[@]+"${FORCE[@]}"}")
  count=$(managed_entries "$REPO/build/$target/agents" | wc -l | tr -d ' ')
  item "⚙" "$G" "build agents" "$count generated"
  for line in "${kept[@]+"${kept[@]}"}"; do
    item "⚠" "$Y" "$line" "edited outside repo · kept (move changes to agents/, then --force)"
    WARNINGS=$(( WARNINGS + 1 ))
  done
  tick

  local src dst_name skip
  for pair in "$@"; do
    IFS=: read -r src dst_name skip <<< "$pair"
    if [[ "$src" == */ ]]; then
      link_dir "$src" "$dir/$dst_name" "$skip"
    else
      link_file "$src" "$dir/$dst_name"
    fi
  done
}

say ""
say "  ${B}agents-config$X$( (( DRY_RUN )) && echo "  ${Y}dry run · nothing changes$X")"
say ""

HAS_CLAUDE=0 HAS_CODEX=0
if found claude "$CLAUDE_DIR"; then
  HAS_CLAUDE=1 TOTAL=$(( TOTAL + 3 + ${#CLAUDE_LINKS[@]} ))
  item "●" "$G" "Claude Code" "found"
else
  item "○" "$D" "Claude Code" "not found · skip"
fi
if found codex "$CODEX_DIR"; then
  HAS_CODEX=1 TOTAL=$(( TOTAL + 3 + ${#CODEX_LINKS[@]} ))
  item "●" "$G" "Codex" "found"
else
  item "○" "$D" "Codex" "not found · skip"
fi

TOTAL=$(( TOTAL + 2 ))  # fetch skills and auto-update steps

if (( TOTAL == 1 )); then
  say ""
  say "  ${Y}Nothing to install: neither Claude Code nor Codex found.$X"
  exit 1
fi

fetch_skills
if (( HAS_CLAUDE )); then
  install_tool claude "Claude Code" "$CLAUDE_DIR" "${CLAUDE_LINKS[@]}"
  install_plugins claude "$CLAUDE_DIR/skills"
  install_mcp claude
fi
if (( HAS_CODEX )); then
  install_tool codex "Codex" "$CODEX_DIR" "${CODEX_LINKS[@]}"
  # skills.sh installs into ~/.agents/skills, which Codex also reads.
  install_plugins codex "$CODEX_DIR/skills" "$HOME/.agents/skills"
  install_mcp codex
fi

say ""
auto_update
tick

summary=""
for part in "$LINKED linked" "$RELINKED relinked" "$BACKED_UP backed up" \
  "$UP_TO_DATE up to date" "$WARNINGS warnings"; do
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
