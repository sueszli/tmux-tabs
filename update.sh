#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# require an installed copy
[ -f "${HOME:?}/.local/bin/tabs" ] || { echo 'install tabs first.' >&2; exit 1; }
# run the latest installer
curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
