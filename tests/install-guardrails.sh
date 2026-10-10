#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home space '\"quote" XDG_CONFIG_HOME=$sandbox/config
export CLAUDE_CONFIG_DIR=$HOME/.claude CODEX_HOME=$HOME/.codex PI_CODING_AGENT_DIR=$HOME/.pi/agent
export TABS_TEST_REPO=$repo TABS_TEST_LOG=$sandbox/downloads
export SHELL=/bin/zsh ZDOTDIR="$sandbox/zsh config"
unset TABS_REVISION
mkdir -p "$sandbox/bin" "$HOME/.local/bin"
mkdir -p "$ZDOTDIR"
printf 'export KEEP_ME=1\n' >"$ZDOTDIR/.zshrc"
export PATH=$sandbox/bin:$PATH
# mock network and hooks
cat >"$sandbox/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url=$2
printf '%s\n' "$url" >> "$TABS_TEST_LOG"
case $url in
    */commits/master) printf '{"sha":"1111111111111111111111111111111111111111"}\n' ;;
    */tmux-tabs.sh) printf 'tabs_install_hooks() { :; }\n' > "$4" ;;
    */guardrails.sh)
        [ "${TABS_TEST_FAIL_DOWNLOAD:-0}" = 0 ] || exit 1
        cp "$TABS_TEST_REPO/guardrails.sh" "$4" ;;
    */install.sh) while IFS= read -r line; do printf '%s\n' "$line"; done < "$TABS_TEST_REPO/install.sh" ;;
    *) exit 1 ;;
esac
MOCK
printf '#!/usr/bin/env bash\nexit 0\n' >"$sandbox/bin/tmux"
chmod +x "$sandbox/bin/"*
printf '#!/usr/bin/env bash\nexit 99\n' >"$HOME/.local/bin/codex"
chmod +x "$HOME/.local/bin/codex"

# every install sets up all three harnesses
bash "$repo/install.sh"
cmp "$ZDOTDIR/.zshrc.before-tabs" <(printf 'export KEEP_ME=1\n')
grep -q '^alias codex=' "$ZDOTDIR/.zshrc"
cmp "$HOME/.local/bin/codex" <(printf '#!/usr/bin/env bash\nexit 99\n')
cp "$ZDOTDIR/.zshrc" "$sandbox/zshrc"
for file in "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$CODEX_HOME/AGENTS.md" "$PI_CODING_AGENT_DIR/AGENTS.md"; do
    grep -q 'An explicit request IS authorization' "$file"
done
[ -f "$HOME/.local/share/tmux-tabs/guardrails.sh" ]
grep -qx 'https://raw.githubusercontent.com/sueszli/tmux-tabs/1111111111111111111111111111111111111111/tmux-tabs.sh' "$TABS_TEST_LOG"
grep -qx 'https://raw.githubusercontent.com/sueszli/tmux-tabs/1111111111111111111111111111111111111111/guardrails.sh' "$TABS_TEST_LOG"

# updates migrate rules and preserve other instructions
printf '<!-- BEGIN USER GIT APPROVAL RULES -->\nOld rules\n<!-- END USER GIT APPROVAL RULES -->\nKeep Claude instructions\n' >"$CLAUDE_CONFIG_DIR/CLAUDE.md"
printf '<!-- BEGIN TMUX-TABS SHARED RULES -->\nStale rules\n<!-- END TMUX-TABS SHARED RULES -->\nKeep Codex instructions\n' >"$CODEX_HOME/AGENTS.md"
bash "$repo/update.sh"
cmp "$sandbox/zshrc" "$ZDOTDIR/.zshrc"
grep -q 'Keep Claude instructions' "$CLAUDE_CONFIG_DIR/CLAUDE.md"
grep -q 'Keep Codex instructions' "$CODEX_HOME/AGENTS.md"
if grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md"; then exit 1; fi
if grep -q 'Stale rules' "$CODEX_HOME/AGENTS.md"; then exit 1; fi
grep -q 'Old rules' "$CLAUDE_CONFIG_DIR/CLAUDE.md.before-tabs-rules"
cp "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$sandbox/updated"
bash "$repo/update.sh"
cmp "$sandbox/updated" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
# failed downloads leave installed files intact
cp "$HOME/.local/bin/tabs" "$sandbox/tabs"
cp "$HOME/.local/share/tmux-tabs/guardrails.sh" "$sandbox/module"
if TABS_TEST_FAIL_DOWNLOAD=1 bash "$repo/install.sh" 2>/dev/null; then exit 1; fi
cmp "$sandbox/tabs" "$HOME/.local/bin/tabs"
cmp "$sandbox/module" "$HOME/.local/share/tmux-tabs/guardrails.sh"
cmp "$sandbox/updated" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
if TABS_REVISION=invalid bash "$repo/install.sh" 2>/dev/null; then exit 1; fi
SHELL=/bin/bash bash "$repo/install.sh"
grep -q '^alias codex=' "$HOME/.profile"
printf '#!/usr/bin/env bash\nexit 99\n' >"$sandbox/bin/codex"
chmod +x "$sandbox/bin/codex"
bash -ic codex 2>/dev/null
bash --rcfile "$HOME/.profile" -ic codex 2>/dev/null
if command -v zsh >/dev/null; then
    zsh -ic codex 2>/dev/null
fi
printf 'installer guardrails tests passed\n'
