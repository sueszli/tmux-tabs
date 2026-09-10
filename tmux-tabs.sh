#!/bin/bash
# tmux-tabs: tmux stripped down to browser-style tabs. no prefix, no panes.
# own socket, so ~/.tmux.conf is untouched. attaches if already running.
exec tmux -L tabs -f <(cat <<'CONF'
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename off
set -g status-position top
set -g status-style 'bg=colour236,fg=colour245'
set -g status-left ''
set -g status-right '#[fg=colour240] ^T new  ^W close  ^← ^→ switch '
set -g window-status-format ' #I #W '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #W '
bind -n C-t display-menu -T ' new tab ' claude c 'new-window -n claude claude' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
CONF
) new-session -A -s tabs -n shell "$@"
