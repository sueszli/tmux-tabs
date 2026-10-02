#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

[ -f "${HOME:?}/.local/bin/tabs" ] || {
    echo 'install tabs first' >&2
    exit 1
}

curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
