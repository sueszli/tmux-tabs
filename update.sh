#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

[ -f "${HOME:?}/.local/bin/tabs" ]

curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
