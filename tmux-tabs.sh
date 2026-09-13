#!/bin/bash
menu="display-menu -T ' new tab ' claude c 'new-window -n claude claude --permission-mode auto' codex x 'new-window -n codex codex' pi p 'new-window -n pi pi' opencode o 'new-window -n opencode opencode' '' shell s 'new-window -n shell'"
exec tmux -L tabs -f <(cat <<CONF
# tabs only: no prefix, no panes, no copy mode
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename off

# tab bar
set -g status-position top
set -g status-style 'bg=colour236,fg=colour245'
set -g status-left ''
set -g status-right '#[fg=colour240] ^T new  ^W close  ^← ^→ switch '
set -g window-status-format ' #I #W '
set -g window-status-current-format '#[bg=colour250,fg=colour236,bold] #I #W '

# new-tab menu
bind -n C-t $menu
bind -n C-n $menu

# close tab
bind -n C-w kill-window

# switch tabs
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window

# jump to tab n
bind -n M-1 select-window -t 1
bind -n M-2 select-window -t 2
bind -n M-3 select-window -t 3
bind -n M-4 select-window -t 4
bind -n M-5 select-window -t 5
bind -n M-6 select-window -t 6
bind -n M-7 select-window -t 7
bind -n M-8 select-window -t 8
bind -n M-9 select-window -t 9

# reorder tabs
bind -n M-S-Left swap-window -d -t -1
bind -n M-S-Right swap-window -d -t +1
CONF
) new-session -A -s tabs -n shell "$@"
