#!/usr/bin/env bash
# a path-level stub also catches tmux calls made from subshells
set -euo pipefail
printf '%s\n' "$*" >>"$TMUX_CALLS"
[ "${1:-}" != -L ] || shift 2
case ${1:-} in
    display-message) [ "${TMUX_PANE_VALID:-1}" != 0 ] || exit 1; printf '@1\n' ;;
    list-windows) printf '@1\n' ;;
    list-panes) printf '%s\n' "$TMUX_STATES" ;;
    set-option | refresh-client) ;;
    *)
        printf 'Unexpected tmux command: %s\n' "$*" >&2
        exit 1
        ;;
esac
