#!/usr/bin/env bash

resize() (
    # resync terminal size after ssh misses a resize
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}') || exit 1
    [ -e "$tty" ] || exit 1

    # serialize terminal size queries
    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    # read the reply without echo
    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo

    # query terminal size through tmux
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    # parse rows and columns
    rows=${reply#*'[8;'}
    rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') exit 1 ;; esac

    # update the client tty
    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null || stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client
    exit 0
)

tab_label() {
    # show the program name behind a node launcher
    local root=$1 fallback=$2 pane=$3 agent state marker
    agent=$(tmux -L tabs show-option -p -v -t "$pane" @tabs_agent 2>/dev/null)
    state=$(tmux -L tabs show-option -p -v -t "$pane" @tabs_state 2>/dev/null)
    if [ -z "$agent" ]; then
        agent=$(ps -e -o pid=,ppid=,comm= | awk -v root="$root" -v fallback="$fallback" '
        { parent[$1] = $2; command[$1] = $3 }
        END {

            # find programs descended from the pane shell
            for (pid in parent) {
                current = pid
                while (current != root && current in parent) current = parent[current]
                if (current == root && command[pid] ~ /(^|\/)(codex|claude)$/) {
                    sub(/^.*\//, "", command[pid])
                    print command[pid]
                    exit
                }
            }
            print fallback
        }
    ')
    fi
    marker='•'
    if [ "$state" = working ] && [ $(( $(date +%s) % 2 )) -eq 1 ]; then
        marker=' '
    fi
    printf '%s %s\n' "$marker" "$agent"
}

tmux_config() {
    # print the config for the tabs server
    local self
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

    cat <<CONF
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename on
set -g allow-passthrough on

# tab bar
set -g status-position top
set -g status-interval 1
set -g status-style 'bg=colour236,fg=colour245'
set -g window-status-current-style 'bg=colour250,fg=colour236,bold'
set -g status-left ''
set -g status-right ' ^T shell  ^W close  ^← ^→ switch '
set -g window-status-format ' #(BASH_ENV=$self bash -c "tab_label #{pane_pid} #{pane_current_command} #{pane_id}") '
set -g window-status-current-format ' #(BASH_ENV=$self bash -c "tab_label #{pane_pid} #{pane_current_command} #{pane_id}") '

# tab keys
bind -n C-t new-window -c '#{pane_current_path}'
bind -n C-n new-window -c '#{pane_current_path}'
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window

# redraw after opening or switching tabs
set-hook -g after-select-window "run-shell -b \"BASH_ENV=$self bash -c 'render #{pane_id}'\""
set-hook -g after-new-window "run-shell -b \"BASH_ENV=$self bash -c 'render #{pane_id}'\""
CONF
}

render() {
    # reload config, correct shell size and redraw tab labels
    local pane=$1 pane_cmd file helper

    # load the latest installed config
    file=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || return 1
    tmux_config > "$file"
    tmux -L tabs source-file "$file" || { rm -f "$file"; return 1; }
    rm -f "$file"
    helper=${BASH_SOURCE[0]%/*}/tabs-agent-hook
    [ -x "$helper" ] && "$helper" refresh >/dev/null

    # query terminal size only from a shell
    pane_cmd=$(tmux -L tabs display-message -p -t "$pane" '#{pane_current_command}') || return 0
    case $pane_cmd in
        *sh) tmux -L tabs send-keys -t "$pane" " env BASH_ENV=${BASH_SOURCE[0]} bash -c resize >/dev/null 2>&1; clear" Enter ;;
    esac

    # refresh every tab label
    tmux -L tabs refresh-client
}

# tmux callbacks source these functions through BASH_ENV
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    exec tmux -L tabs -f <(tmux_config) new-session -A -s tabs
fi
