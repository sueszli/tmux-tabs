#!/bin/bash

resize() (
    # ssh can lose resize notifications between the terminal and tmux
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}') || exit 1
    [ -e "$tty" ] || exit 1

    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo

    # ask the terminal for its size through tmux
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    rows=${reply#*'[8;'}
    rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') exit 1 ;; esac

    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null || stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client
    exit 0
)

tab_label() {
    local root=$1 fallback=$2
    ps -e -o pid=,ppid=,comm= | awk -v root="$root" -v fallback="$fallback" '
        { parent[$1] = $2; command[$1] = $3 }
        END {
            for (pid in parent) {
                current = pid
                while (current != root && current in parent) current = parent[current]
                if (current == root && command[pid] ~ /(^|\/)codex$/) {
                    print "codex"
                    exit
                }
            }
            print fallback
        }
    '
}

tmux_config() {
    local self
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

    cat <<CONF
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename on
set -g allow-passthrough on
set -g status-position top
set -g status-style 'bg=colour236,fg=colour245'
set -g status-left ''
set -g status-right '#[fg=colour240] ^T shell  ^W close  ^← ^→ switch '
set -g window-status-format ' #I #($self --label #{pane_pid} #{pane_current_command}) '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #($self --label #{pane_pid} #{pane_current_command}) '
bind -n C-t new-window -c '#{pane_current_path}'
bind -n C-n new-window -c '#{pane_current_path}'
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window
set-hook -g after-select-window "run-shell -b '$self --render #{pane_id}'"
set-hook -g after-new-window "run-shell -b '$self --render #{pane_id}'"
CONF
}

render() {
    local pane=$1 pane_cmd file

    # the installed script may have changed since this tmux server started
    file=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || return 1
    tmux_config > "$file"
    tmux -L tabs source-file "$file" || { rm -f "$file"; return 1; }
    rm -f "$file"

    pane_cmd=$(tmux -L tabs display-message -p -t "$pane" '#{pane_current_command}') || return 0
    case $pane_cmd in
        *sh) tmux -L tabs send-keys -t "$pane" " env BASH_ENV=$0 bash -c resize >/dev/null 2>&1; clear" Enter ;;
    esac

    # redrawing the bar runs tab_label for each tab
    tmux -L tabs refresh-client
}

# the resize command loads this file through BASH_ENV inside a shell pane
if [ "${1:-}" = --label ]; then
    tab_label "$2" "$3"
elif [ "${1:-}" = --render ]; then
    render "$2"
elif [ "${BASH_SOURCE[0]}" = "$0" ]; then
    exec tmux -L tabs -f <(tmux_config) new-session -A -s tabs
fi
