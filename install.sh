#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# stage the download
target="${HOME:?}/.local/bin/tabs"
command -v tmux >/dev/null || { echo 'tabs needs tmux 3.0+' >&2; exit 1; }
command -v jq >/dev/null || { echo 'agent status setup needs jq' >&2; exit 1; }
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# download and install
curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/tmux-tabs.sh -o "$tmp"
bash -n "$tmp"
chmod +x "$tmp"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
    echo "installed tabs at $target"
fi
BASH_ENV="$target" bash -c tabs_install_hooks

for shim in "${target%/*}/codex" "$HOME/bin/codex"; do
    [ -d "${shim%/*}" ] || continue
    if [ ! -e "$shim" ] && [ ! -L "$shim" ]; then
        ln -s "$target" "$shim"
        echo "installed Codex tabs shim at $shim"
    elif [ ! "$shim" -ef "$target" ]; then
        echo "skipped Codex tabs shim: $shim already exists" >&2
    fi
done
