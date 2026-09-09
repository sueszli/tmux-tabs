#!/bin/bash
# tmux-tabs: tmux stripped down to browser-style tabs. no prefix, no panes.
# own socket, so ~/.tmux.conf is untouched. attaches if already running.
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
