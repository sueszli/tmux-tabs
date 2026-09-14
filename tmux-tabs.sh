#!/bin/bash

# ctrl+space asks the terminal how big it is and resizes the tabs to match.
#
# ssh only sends the window size at connect time; after that it relies on
# SIGWINCH, which can get lost across ssh hops. When that happens tmux keeps
# filling the size it was told at connect, so tabs look stuck at a fixed width.
# Asking the terminal directly and applying the answer fixes it.
#
# Must run in the foreground: reading the terminal's answer means owning the
# terminal, and a background job that does that gets stopped with SIGTTOU.
if [ "$1" = "--resize" ]; then
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}' 2>/dev/null)
    [ -n "$tty" ] && [ -e "$tty" ] || { echo "tabs: no tmux client" >&2; exit 1; }

    # Ask the terminal for its size and read the answer. The DCS wrapper makes
    # the query pass through tmux to the real terminal outside it. Echo is off
    # so the answer is not printed, and read stops at the 't' that ends it.
    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    # the answer looks like: ESC [ 8 ; rows ; cols t
    case $reply in
        *'[8;'*';'*) ;;
        *) echo "tabs: terminal did not report its size" >&2; exit 1 ;;
    esac
    rows=${reply#*'[8;'}; rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') echo "tabs: bad size reply" >&2; exit 1 ;; esac

    # Setting the size raises SIGWINCH, which is what makes tmux resize. -F is
    # GNU stty, -f is BSD/macOS.
    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null ||
        stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client -S 2>/dev/null
    exit 0
fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
menu="display-menu -T ' new tab ' claude c 'new-window -n claude claude --permission-mode auto' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'"
# Only in a shell tab: send-keys into an agent tab would type into the agent.
resize="if-shell -F '#{m:*sh,#{pane_current_command}}' \"send-keys '$self --resize' Enter\" \"display-message 'ctrl+space: use a shell tab to resync size'\""
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
bind -n C-Space $resize
CONF
) new-session -A -s tabs -n shell "$@"
