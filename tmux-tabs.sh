#!/bin/bash

# Switching tabs resyncs the size: ask the terminal how big it is and resize to
# match. Needed when SIGWINCH is lost across ssh hops, which leaves tabs stuck at
# whatever size they had at connect time.
if [ "$1" = "--resize" ]; then
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}' 2>/dev/null)
    [ -n "$tty" ] && [ -e "$tty" ] || { echo "tabs: no tmux client" >&2; exit 1; }

    # Switching tabs quickly can start a second query while the first is still
    # waiting for its answer; the stray answer would then be echoed into a
    # shell. Let one run at a time and drop the rest.
    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    # answer: ESC [ 8 ; rows ; cols t
    case $reply in
        *'[8;'*';'*) ;;
        *) echo "tabs: terminal did not report its size" >&2; exit 1 ;;
    esac
    rows=${reply#*'[8;'}; rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') echo "tabs: bad size reply" >&2; exit 1 ;; esac

    # this raises SIGWINCH, which is what resizes tmux. -F is GNU, -f is BSD
    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null ||
        stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client -S 2>/dev/null
    exit 0
fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
# Resync on every tab switch. Shell tabs only, because this types a command: in
# an agent tab it would go to the agent. The leading space keeps it out of
# history and clear wipes the line, so the tab just looks like a fresh prompt.
fit="if-shell -F '#{m:*sh,#{pane_current_command}}' \\\"send-keys ' $self --resize >/dev/null 2>&1; clear' Enter\\\" ''"
menu="display-menu -T ' new tab ' claude c 'new-window -n claude claude --permission-mode auto' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'"
exec tmux -L tabs -f <(cat <<CONF
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename off
set -g allow-passthrough on
set -g status-position top
set -g status-style 'bg=colour236,fg=colour245'
set -g status-left ''
set -g status-right '#[fg=colour240] ^T new  ^W close  ^← ^→ switch '
set -g window-status-format ' #I #W '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #W '
bind -n C-t $menu
bind -n C-n $menu
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window
set-hook -g after-select-window "$fit"
CONF
) new-session -A -s tabs -n shell "$@"
