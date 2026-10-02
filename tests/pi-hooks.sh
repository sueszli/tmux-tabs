#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" PI_CODING_AGENT_DIR="$tmp/custom pi"
mkdir -p "$HOME" "$tmp/bin" "$tmp/path with 'quotes'"
cp "$root/tmux-tabs.sh" "$tmp/path with 'quotes'/tabs"
source "$tmp/path with 'quotes'/tabs"

tabs_install_hooks
extension="$PI_CODING_AGENT_DIR/extensions/tmux-tabs.js"
test -f "$extension"
test ! -e "$HOME/.pi/agent/extensions/tmux-tabs.js"
cp "$extension" "$tmp/first.js"
tabs_install_hooks
cmp "$extension" "$tmp/first.js"
test ! -e "$extension.before-tabs"
printf '// old extension\n' > "$extension"
tabs_install_hooks
grep -Fx '// old extension' "$extension.before-tabs"
cmp "$extension" "$tmp/first.js"

unset PI_CODING_AGENT_DIR
tabs_install_pi_hooks "$root/tmux-tabs.sh"
test -f "$HOME/.pi/agent/extensions/tmux-tabs.js"

cat > "$tmp/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_LOG"
case $3 in
    display-message) printf '@1\n' ;;
    list-panes) printf '%s\n' "${MOCK_STATE:-idle}" ;;
esac
MOCK
chmod +x "$tmp/bin/tmux"
export PATH="$tmp/bin:$PATH" TMUX_LOG="$tmp/tmux.log"
export TMUX='/tmp/tmux-1000/tabs,123,0' TMUX_PANE='%1'
for pair in 'SessionStart idle' 'UserPromptSubmit working' 'Stop feedback'; do
    read -r event state <<< "$pair"
    : > "$TMUX_LOG"
    MOCK_STATE=$state tabs_agent_hook pi "$event" > "$tmp/result"
    grep -F -- '-p -t %1 @tabs_agent pi' "$TMUX_LOG"
    grep -F -- "-p -t %1 @tabs_state $state" "$TMUX_LOG"
    grep -Fx '{}' "$tmp/result"
    if [ "$state" = feedback ]; then
        grep -F 'window-status-current-style bg=colour34,fg=colour232,bold' "$TMUX_LOG"
    else
        grep -F -- '-wu -t @1 window-status-current-style' "$TMUX_LOG"
    fi
done
: > "$TMUX_LOG"
tabs_agent_hook pi SessionEnd >/dev/null
grep -F -- '-p -u -t %1 @tabs_agent' "$TMUX_LOG"
grep -F -- '-p -u -t %1 @tabs_state' "$TMUX_LOG"
: > "$TMUX_LOG"
TMUX='/tmp/tmux-1000/default,123,0' tabs_agent_hook pi Stop >/dev/null
test ! -s "$TMUX_LOG"

node "$root/tests/pi-extension.mjs" "$extension"
printf 'Pi hook tests passed\n'
