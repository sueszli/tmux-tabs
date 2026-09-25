#!/usr/bin/env bash
set -euo pipefail

target=${HOME:?}/.local/bin/tabs
if [ ! -f "$target" ]; then
    echo "tabs is not installed at $target. Run install.sh first." >&2
    exit 1
fi

curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/install.sh | bash
