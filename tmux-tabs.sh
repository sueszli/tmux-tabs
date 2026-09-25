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
    tmux refresh-client -S
    exit 0
)

tmux_config() {
    local self fit
    self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

    # load this file in bash so the pane can call resize
    fit="if-shell -F '#{m:*sh,#{pane_current_command}}' \\\"send-keys ' env BASH_ENV=$self bash -c resize >/dev/null 2>&1; clear' Enter\\\" ''"

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
set -g window-status-format ' #I #{pane_current_command} '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #{pane_current_command} '
bind -n C-t new-window
bind -n C-n new-window
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window
set-hook -g after-select-window "$fit"
CONF
}

# start tmux only when run directly because the resize hook loads this file
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    exec tmux -L tabs -f <(tmux_config) new-session -A -s tabs
fi
