#!/bin/bash

# ctrl+space: resync the tab size to the terminal.
#
# ssh sends the window size once at connect and relies on SIGWINCH for later
# resizes. Across some links (nested ssh hops, flaky clients) that signal never
# arrives, so every layer stays pinned at the connect-time size and tmux fills
# stale geometry - tabs look stuck at a fixed width no matter how you resize.
#
# This asks the terminal how big it really is (CSI 18t, wrapped in the tmux
# passthrough sequence so it reaches the outer terminal) and writes that size
# onto the client tty. The kernel then raises the SIGWINCH that went missing and
# tmux resizes every window and pane through its normal path.
#
# It must run in the foreground: reading a reply requires owning the terminal,
# and a background job that touches the tty is stopped with SIGTTOU.
if [ "$1" = "--resize" ]; then
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}' 2>/dev/null)
    [ -n "$tty" ] && [ -e "$tty" ] || { echo "tabs: no tmux client" >&2; exit 1; }

    # Take the terminal before asking it anything. The reply is ordinary input,
    # so if it lands while the shell's line editor is still active it gets
    # echoed and run as a stray command. Switching to raw -echo first closes
    # that window; reading byte by byte then stops at the report terminator, and
    # the short drain absorbs a duplicate report before echo comes back.
    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty

    # Read byte by byte up to the report terminator. The -t timeout keeps a
    # terminal that never answers from wedging the tab.
    reply=''
    while IFS= read -r -n 1 -t 3 ch; do
        reply=$reply$ch
        [ "$ch" = t ] && break
    done

    # Absorb a duplicate report before echo comes back, or it is run as a
    # command. bash 3.2 (still the /bin/bash on macOS) only accepts whole-second
    # timeouts, so pick the smallest value this bash understands.
    if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then drain=0.1; else drain=1; fi
    while IFS= read -r -n 1 -t "$drain" _; do :; done
    stty "$saved"

    case $reply in
        *'[8;'*';'*) ;;
        *) echo "tabs: terminal did not report its size" >&2; exit 1 ;;
    esac
    rows=${reply#*'[8;'}; rows=${rows%%;*}
    cols=${reply##*;};    cols=${cols%t}
    case $rows$cols in *[!0-9]*|'') echo "tabs: bad size reply" >&2; exit 1 ;; esac

    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null ||
        stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client -S 2>/dev/null
    exit 0
fi

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
menu="display-menu -T ' new tab ' claude c 'new-window -n claude claude --permission-mode auto' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'"
# Typing into an agent tab would corrupt its input, so only fire in a shell.
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
