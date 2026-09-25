#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# stage the download
target="${HOME:?}/.local/bin/tabs"
helper="${target}-agent-hook"
base=https://raw.githubusercontent.com/sueszli/tmux-tabs/master
command -v tmux >/dev/null || { echo 'tabs needs tmux 3.0+' >&2; exit 1; }
command -v jq >/dev/null || { echo 'agent status setup needs jq' >&2; exit 1; }
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
hook_tmp=$(mktemp "${helper}.XXXXXX")
trap 'rm -f "$tmp" "$hook_tmp"' EXIT

# download and install
curl -fsSL "$base/tmux-tabs.sh" -o "$tmp"
curl -fsSL "$base/tabs-agent-hook" -o "$hook_tmp"
bash -n "$tmp"
bash -n "$hook_tmp"
chmod +x "$tmp"
chmod +x "$hook_tmp"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
    echo "installed tabs at $target"
fi
if ! cmp -s "$hook_tmp" "$helper" || [ ! -x "$helper" ]; then
    mv "$hook_tmp" "$helper"
    echo "installed agent hook at $helper"
fi
"$helper" install
