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

# installs sync rules; launches do not
grep -q 'bash .*guardrails.sh' "$repo/install.sh"
if grep -q 'tabs_sync_rules --migrate' "$repo/tmux-tabs.sh"; then exit 1; fi
printf 'Claude-only instruction\n' >"$CLAUDE_CONFIG_DIR/CLAUDE.md"
chmod 640 "$CLAUDE_CONFIG_DIR/CLAUDE.md"
run --dry-run >/dev/null
[ ! -e "$CODEX_HOME/AGENTS.md" ]
[ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules" ]
run
# verify faithful syncing of the whole policy, not individual prose choices
source "$repo/guardrails.sh"
printf '%s\n' "$TABS_DEFAULT_POLICY" >"$sandbox/expected-policy"
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    awk '
        /^<!-- BEGIN TMUX-TABS SHARED RULES -->$/ { inside=1; next }
        /^<!-- END TMUX-TABS SHARED RULES -->$/ { inside=0; next }
        inside { print }
    ' "$file" >"$sandbox/actual-policy"
    cmp "$sandbox/expected-policy" "$sandbox/actual-policy"
done
grep -q 'Claude-only instruction' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
[ "$(find "$CLAUDE_CONFIG_DIR" -name CLAUDE.md -perm 0640)" = "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
cmp "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules" <(printf 'Claude-only instruction\n')
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/first"
run
cmp "$sandbox/first" "$CLAUDE_CONFIG_DIR/CLAUDE.md"

# custom policies preserve other instructions
mkdir -p "$XDG_CONFIG_HOME/agents"
printf 'Custom policy without trailing newline' >"$XDG_CONFIG_HOME/agents/AGENTS.md"
run
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -qx 'Custom policy without trailing newline' "$file"
    if grep -q 'An explicit request IS authorization' "$file"; then exit 1; fi
done
printf 'Explicit policy\n' >"$sandbox/policy.md"
run "$sandbox/policy.md"
grep -qx 'Explicit policy' "$CODEX_HOME/AGENTS.md"

# migrate legacy rules
printf '<!-- BEGIN USER GIT APPROVAL RULES -->\nOld rules\n<!-- END USER GIT APPROVAL RULES -->\nClaude-only instruction\n' >"$CLAUDE_CONFIG_DIR/CLAUDE.md"
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/legacy"
run --dry-run >/dev/null
cmp "$sandbox/legacy" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
run
grep -q 'Claude-only instruction' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
if grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md"; then exit 1; fi
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/before-failure"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\nUnclosed\n' >"$PI_CODING_AGENT_DIR/AGENTS.md"
if run 2>/dev/null; then
    printf 'unclosed block should fail\n' >&2
    exit 1
fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
rm "$PI_CODING_AGENT_DIR/AGENTS.md"
ln -s "$sandbox/before-failure" "$PI_CODING_AGENT_DIR/AGENTS.md"
if run 2>/dev/null; then
    printf 'symlink should fail\n' >&2
    exit 1
fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
rm "$PI_CODING_AGENT_DIR/AGENTS.md"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\n' >"$XDG_CONFIG_HOME/agents/AGENTS.md"
if run 2>/dev/null; then
    printf 'source markers should fail\n' >&2
    exit 1
fi
: >"$XDG_CONFIG_HOME/agents/AGENTS.md"
if run 2>/dev/null; then
    printf 'empty source should fail\n' >&2
    exit 1
fi
# reject unsafe backups
printf 'Replacement policy\n' >"$XDG_CONFIG_HOME/agents/AGENTS.md"
rm "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules"
ln -s "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules"
if run 2>/dev/null; then
    printf 'backup symlink should fail\n' >&2
    exit 1
fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
rm "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules"

# inject a one-shot failure after the first replacement
mkdir -p "$sandbox/bin"
TABS_TEST_MV=$(command -v mv)
export TABS_TEST_MV TABS_TEST_FAIL=$sandbox/fail
cat >"$sandbox/bin/mv" <<'MOCK'
#!/usr/bin/env bash
if [ "${!#}" = "$CODEX_HOME/AGENTS.md" ] && [ ! -e "$TABS_TEST_FAIL" ]; then
    touch "$TABS_TEST_FAIL"
    exit 1
fi
exec "$TABS_TEST_MV" "$@"
MOCK
chmod +x "$sandbox/bin/mv"
export PATH=$sandbox/bin:$PATH
cp "$CODEX_HOME/AGENTS.md" "$sandbox/codex"
if run 2>/dev/null; then
    printf 'rename should fail\n' >&2
    exit 1
fi
cmp "$sandbox/before-failure" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
cmp "$sandbox/codex" "$CODEX_HOME/AGENTS.md"
[ ! -e "$PI_CODING_AGENT_DIR/AGENTS.md" ]

# unchanged destinations survive rollback
run
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/unchanged"
printf 'Old codex instructions\n' >"$CODEX_HOME/AGENTS.md"
rm "$TABS_TEST_FAIL"
if run 2>/dev/null; then exit 1; fi
cmp "$sandbox/unchanged" "$CLAUDE_CONFIG_DIR/CLAUDE.md"

# rollback removes newly created files too
rm "$TABS_TEST_FAIL" "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"
if run 2>/dev/null; then exit 1; fi
[ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
[ ! -e "$CODEX_HOME/AGENTS.md" ]
[ ! -e "$PI_CODING_AGENT_DIR/AGENTS.md" ]
run
run
[ -z "$(find "$HOME" -name '*.tabs.*')" ]

# missing explicit policies must not install defaults
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/unchanged"
if run "$sandbox/missing.md" 2>/dev/null; then exit 1; fi
cmp "$sandbox/unchanged" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
printf 'shared-rules tests passed\n'
