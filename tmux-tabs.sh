#!/bin/bash

# ssh hops can swallow SIGWINCH, leaving tabs stuck at the connect-time size
# ask the terminal how big it is (CSI 18t) and apply that on every tab switch
if [ "$1" = "--resize" ]; then
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}') || exit 1
    [ -e "$tty" ] || exit 1

    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    rows=${reply#*'[8;'}; rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') exit 1 ;; esac

    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null ||
        stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client -S
    exit 0
fi

if [ "$1" = "--agent" ]; then
    case $2 in
        claude) set -- claude --dangerously-skip-permissions ;;
        codex) set -- codex --dangerously-bypass-approvals-and-sandbox -C "$PWD" ;;
        *) echo "Unknown agent: $2" >&2; exit 2 ;;
    esac
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        set -- "$@" --worktree
    fi
    exec "$@"
fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
# shell tabs only: in an agent tab these keys would go to the agent
fit="if-shell -F '#{m:*sh,#{pane_current_command}}' \\\"send-keys ' $self --resize >/dev/null 2>&1; clear' Enter\\\" ''"
menu="display-menu -T ' agents in #{b:pane_current_path} ' 'Claude (bypass, worktree if Git)' c 'new-window -n claude -c \"#{pane_current_path}\" \"$self --agent claude\"' 'Codex (yolo, worktree if Git)' x 'new-window -n codex -c \"#{pane_current_path}\" \"$self --agent codex\"'"
config() { cat <<CONF
set -g prefix C-b
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename off
setw -g remain-on-exit on
set -g allow-passthrough on
set -g status-position top
set -g status-style 'bg=colour236,fg=colour245'
set -g status-left ''
set -g status-right-length 32
set -g status-right '#[fg=colour240] ^B t shell  ^B a agents  ^B g cwd '
set -g window-status-format ' #I #W:#{b:pane_current_path} '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #W:#{b:pane_current_path} '
unbind -qn C-w
unbind -qn C-f
unbind -qn C-b
unbind -qn C-Right
unbind -qn C-Left
bind t new-window -n shell -c '#{pane_current_path}'
bind a $menu
bind g display-message -d 5000 'cwd: #{pane_current_path}'
bind w kill-window
bind Right next-window
bind Left previous-window
bind -n C-t $menu
bind -n C-n $menu
set-hook -g after-select-window "$fit"
CONF
}

reload() (
    local file
    file=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || exit 1
    trap 'rm -f "$file"' EXIT
    config > "$file"
    tmux -L tabs source-file "$file"
)

if [ "$1" = "--reload" ]; then
    reload
    exit
fi
if tmux -L tabs has-session 2>/dev/null; then
    reload
fi
exec tmux -L tabs -f <(config) new-session -A -s tabs -n shell "$@"
