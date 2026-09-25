#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# require an existing installation before running the installer again.
[ -f "${HOME:?}/.local/bin/tabs" ] || { echo 'install tabs first.' >&2; exit 1; }
# download and run the current installer.
curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
