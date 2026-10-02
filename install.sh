#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

#
# setup
#

target="${HOME:?}/.local/bin/tabs"
command -v tmux >/dev/null || {
    echo 'tmux 3.0+ required' >&2
    exit 1
}
command -v jq >/dev/null || {
    echo 'jq required' >&2
    exit 1
}
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

#
# installation
#

curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/tmux-tabs.sh -o "$tmp"
bash -n "$tmp"
chmod +x "$tmp"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
    echo "installed $target"
fi
BASH_ENV="$target" bash -c tabs_install_hooks
BASH_ENV="$target" bash -c tabs_sync_rules

#
# codex shim
#

for shim in "${target%/*}/codex" "$HOME/bin/codex"; do
    [ -d "${shim%/*}" ] || continue
    if [ ! -e "$shim" ] && [ ! -L "$shim" ]; then
        ln -s "$target" "$shim"
        echo "installed shim $shim"
    elif [ ! "$shim" -ef "$target" ]; then
        echo "skipped shim $shim: exists" >&2
    fi
done
