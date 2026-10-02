#!/usr/bin/env bash
# a path-level stub also catches tmux calls made from subshells.
set -euo pipefail
printf '%s\n' "$*" >>"$TMUX_CALLS"
[ "${1:-}" != -L ] || shift 2
case ${1:-} in
    display-message | list-windows) printf '@1\n' ;;
    list-panes) printf '%s\n' "$TMUX_STATES" ;;
    set-option | refresh-client) ;;
    *)
        printf 'Unexpected tmux command: %s\n' "$*" >&2
        exit 1
        ;;
esac
