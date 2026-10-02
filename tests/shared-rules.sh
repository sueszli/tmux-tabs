#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export HOME=$sandbox/home XDG_CONFIG_HOME=$sandbox/config
export CLAUDE_CONFIG_DIR=$HOME/.claude CODEX_HOME=$HOME/.codex PI_CODING_AGENT_DIR=$HOME/.pi/agent
mkdir -p "$XDG_CONFIG_HOME/agents" "$CLAUDE_CONFIG_DIR"
policy=$XDG_CONFIG_HOME/agents/AGENTS.md
printf '# Shared policy\nOne approval per scoped workflow.\n' > "$policy"
printf '# Claude-only instruction\n' > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
run() { bash "$repo/tmux-tabs.sh" sync-rules "$@"; }
run --dry-run > /dev/null
[ ! -e "$CODEX_HOME/AGENTS.md" ]
[ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules" ]
run
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -q 'One approval per scoped workflow.' "$file"
done
grep -q 'Claude-only' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
[ "$(wc -l < "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules")" -eq 1 ]
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/first"
run
cmp "$sandbox/first" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
printf 'Updated policy without trailing newline' > "$policy"
run
grep -q '^Updated policy without trailing newline$' "$CODEX_HOME/AGENTS.md"
! grep -q 'One approval' "$CODEX_HOME/AGENTS.md"
printf '<!-- BEGIN USER GIT APPROVAL RULES -->\nOld rules\n<!-- END USER GIT APPROVAL RULES -->\nClaude attribution rule\n' > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
if run 2>/dev/null; then echo 'legacy migration should require opt-in' >&2; exit 1; fi
run --migrate-git-rules
grep -q 'Claude attribution rule' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
! grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/before-failure"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\nUnclosed\n' > "$PI_CODING_AGENT_DIR/AGENTS.md"
if run 2>/dev/null; then echo 'unclosed block should fail' >&2; exit 1; fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
rm "$PI_CODING_AGENT_DIR/AGENTS.md"
ln -s "$sandbox/before-failure" "$PI_CODING_AGENT_DIR/AGENTS.md"
if run 2>/dev/null; then echo 'symlink should fail' >&2; exit 1; fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
rm "$PI_CODING_AGENT_DIR/AGENTS.md"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\n' > "$policy"
if run 2>/dev/null; then echo 'source markers should fail' >&2; exit 1; fi
: > "$policy"
if run 2>/dev/null; then echo 'empty source should fail' >&2; exit 1; fi
printf 'shared-rules tests passed\n'
