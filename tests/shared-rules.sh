#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export HOME=$sandbox/home XDG_CONFIG_HOME=$sandbox/config
export CLAUDE_CONFIG_DIR=$HOME/.claude CODEX_HOME=$HOME/.codex PI_CODING_AGENT_DIR=$HOME/.pi/agent
mkdir -p "$CLAUDE_CONFIG_DIR"
mkdir -p "$HOME/.local/share/tmux-tabs"
cp "$repo/guardrails.sh" "$HOME/.local/share/tmux-tabs/guardrails.sh"
run() { bash "$repo/tmux-tabs.sh" sync-rules "$@"; }

# Installation/update syncs the bundled module; ordinary launches do not.
grep -q 'bash "$module_dir/guardrails.sh"' "$repo/install.sh"
! grep -q 'tabs_sync_rules --migrate' "$repo/tmux-tabs.sh"
printf 'Claude-only instruction\n' > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
run --dry-run > /dev/null
[ ! -e "$CODEX_HOME/AGENTS.md" ]
[ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules" ]
run
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -q 'An explicit request IS authorization' "$file"
    grep -q 'if no PR/MR exists, creating one is included' "$file"
    grep -q 'Require separate explicit approval for force-pushing' "$file"
done
grep -q 'Claude-only instruction' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
cmp "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules" <(printf 'Claude-only instruction\n')
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/first"
run
cmp "$sandbox/first" "$CLAUDE_CONFIG_DIR/CLAUDE.md"

# User policies override the bundled policy and retain unrelated instructions.
mkdir -p "$XDG_CONFIG_HOME/agents"
printf 'Custom policy without trailing newline' > "$XDG_CONFIG_HOME/agents/AGENTS.md"
run
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -qx 'Custom policy without trailing newline' "$file"
    ! grep -q 'An explicit request IS authorization' "$file"
done
printf 'Explicit policy\n' > "$sandbox/policy.md"
run "$sandbox/policy.md"
grep -qx 'Explicit policy' "$CODEX_HOME/AGENTS.md"

# Legacy rules are automatically replaced, preserving unrelated instructions.
printf '<!-- BEGIN USER GIT APPROVAL RULES -->\nOld rules\n<!-- END USER GIT APPROVAL RULES -->\nClaude-only instruction\n' > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/legacy"
run --dry-run > /dev/null
cmp "$sandbox/legacy" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
run
grep -q 'Claude-only instruction' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
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
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\n' > "$XDG_CONFIG_HOME/agents/AGENTS.md"
if run 2>/dev/null; then echo 'source markers should fail' >&2; exit 1; fi
: > "$XDG_CONFIG_HOME/agents/AGENTS.md"
if run 2>/dev/null; then echo 'empty source should fail' >&2; exit 1; fi
printf 'shared-rules tests passed\n'
