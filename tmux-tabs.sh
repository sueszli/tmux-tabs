#!/bin/bash
# tmux-tabs: tmux stripped down to browser-style tabs. no prefix, no panes.

# terminal.app doesn't send ⌥ as meta by default. use a "tmux-tabs" profile that does.
# first run: import it (opens a new window running this). after: switch this tab to it.
if [ "$TERM_PROGRAM" = Apple_Terminal ] && [ -z "$TMUX_TABS" ]; then
  if osascript -e 'tell app "Terminal" to exists settings set "tmux-tabs"' | grep -q false; then
    f=$(mktemp -d)/tmux-tabs.terminal
    defaults export com.apple.Terminal - \
      | plutil -extract "Window Settings.$(defaults read com.apple.Terminal 'Default Window Settings')" xml1 -o - - \
      | plutil -replace name -string tmux-tabs -o - - \
      | plutil -replace useOptionAsMetaKey -bool true -o - - \
      | plutil -replace RunCommandAsShell -bool false -o - - \
      | plutil -replace CommandString -string "exec env TMUX_TABS=1 $(readlink -f "$0")" -o "$f" -
    exec open "$f"
  fi
  osascript - "$(tty)" >/dev/null <<'AS'
on run {t}
  tell app "Terminal" to repeat with w in windows
    repeat with tb in tabs of w
      if tty of tb is t then set current settings of tb to settings set "tmux-tabs"
    end repeat
  end repeat
end run
AS
fi

exec tmux -L tabs -f <(cat <<'CONF'
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename off
set -g status-position top
set -g status-left ''
set -g status-right ' ⌥T new  ⌥W close  ⌥⇥ switch '
set -g window-status-format ' #I #W '
set -g window-status-current-format '#[reverse] #I #W '
bind -n M-t display-menu -T ' new tab ' claude c 'new-window -n claude claude' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'
bind -n M-w kill-window
bind -n M-Tab next-window
bind -n M-BTab previous-window
CONF
) new-session -A -s tabs "$@"
