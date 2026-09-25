#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

update_tabs() {
    local target="${HOME:?}/.local/bin/tabs"
    [ -f "$target" ] || { echo "Install tabs first: $target" >&2; return 1; }
    curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
}

update_tabs
