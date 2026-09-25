#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# stage the download
target="${HOME:?}/.local/bin/tabs"
base=https://raw.githubusercontent.com/sueszli/tmux-tabs/master
command -v tmux >/dev/null || { echo 'tabs needs tmux 3.0+' >&2; exit 1; }
command -v jq >/dev/null || { echo 'agent status setup needs jq' >&2; exit 1; }
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# download and install
curl -fsSL "$base/tmux-tabs.sh" -o "$tmp"
bash -n "$tmp"
chmod +x "$tmp"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
    echo "installed tabs at $target"
fi
BASH_ENV="$target" bash -c tabs_install_hooks
