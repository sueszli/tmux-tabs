#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

install_tabs() (
    local target="${HOME:?}/.local/bin/tabs" tmp
    command -v tmux >/dev/null || { echo 'tabs needs tmux 3.0+' >&2; return 1; }
    mkdir -p "${target%/*}"
    tmp=$(mktemp "${target}.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/tmux-tabs.sh -o "$tmp"
    bash -n "$tmp"
    chmod +x "$tmp"
    if cmp -s "$tmp" "$target" && [ -x "$target" ]; then
        echo "tabs is already up to date at $target"
        return
    fi
    mv "$tmp" "$target"
    echo "Installed tabs at $target"
)

install_tabs
