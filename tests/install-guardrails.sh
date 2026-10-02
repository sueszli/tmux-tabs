#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export HOME=$sandbox/home XDG_CONFIG_HOME=$sandbox/config
export CLAUDE_CONFIG_DIR=$HOME/.claude CODEX_HOME=$HOME/.codex PI_CODING_AGENT_DIR=$HOME/.pi/agent
export TABS_TEST_REPO=$repo
mkdir -p "$sandbox/bin" "$HOME/.local/bin"
export PATH=$sandbox/bin:$PATH
# Mock downloads and hook setup: never touch network or real agent configs.
cat > "$sandbox/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url=$2
case $url in
    */tmux-tabs.sh) printf 'tabs_install_hooks() { :; }\n' > "$4" ;;
    */guardrails.sh) cp "$TABS_TEST_REPO/guardrails.sh" "$4" ;;
    */install.sh) while IFS= read -r line; do printf '%s\n' "$line"; done < "$TABS_TEST_REPO/install.sh" ;;
    *) exit 1 ;;
esac
MOCK
for cmd in tmux jq; do printf '#!/usr/bin/env bash\nexit 0\n' > "$sandbox/bin/$cmd"; done
chmod +x "$sandbox/bin/"*

# Fresh installation creates all three global policies.
bash "$repo/install.sh"
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -q 'An explicit request IS authorization' "$file"
done
[ -f "$HOME/.local/share/tmux-tabs/guardrails.sh" ]

# Updates replace legacy and stale managed rules without wiping other content.
printf '<!-- BEGIN USER GIT APPROVAL RULES -->\nOld rules\n<!-- END USER GIT APPROVAL RULES -->\nKeep Claude instructions\n' > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\nStale rules\n<!-- END TMUX-TABS SHARED RULES -->\nKeep Codex instructions\n' > "$CODEX_HOME/AGENTS.md"
bash "$repo/update.sh"
grep -q 'Keep Claude instructions' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
grep -q 'Keep Codex instructions' "$CODEX_HOME/AGENTS.md"
! grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
! grep -q 'Stale rules' "$CODEX_HOME/AGENTS.md"
grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules"
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/updated"
bash "$repo/update.sh"
cmp "$sandbox/updated" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
printf 'installer guardrails tests passed\n'
