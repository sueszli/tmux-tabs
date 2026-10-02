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
# pin both downloads to one revision
revision=${TABS_REVISION:-$(curl -fsSL https://api.github.com/repos/sueszli/tmux-tabs/commits/master | jq -er '.sha')}
[[ $revision =~ ^[0-9a-f]{40}$ ]] || {
    echo 'Invalid tmux-tabs revision' >&2
    exit 1
}
base_url="https://raw.githubusercontent.com/sueszli/tmux-tabs/$revision"
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
module_dir="$HOME/.local/share/tmux-tabs"
mkdir -p "$module_dir"
module_tmp=$(mktemp "$module_dir/guardrails.XXXXXX")
trap 'rm -f "$tmp" "$module_tmp"' EXIT

#
# installation
#

curl -fsSL "$base_url/tmux-tabs.sh" -o "$tmp"
curl -fsSL "$base_url/guardrails.sh" -o "$module_tmp"
bash -n "$tmp"
bash -n "$module_tmp"
chmod +x "$tmp"
mv "$module_tmp" "$module_dir/guardrails.sh"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
    echo "installed $target"
fi
BASH_ENV="$target" bash -c tabs_install_hooks
# install global rules on every install/update
echo 'Installing global Claude, Codex and Pi workflow guardrails (also apply outside tabs).'
bash "$module_dir/guardrails.sh"

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
