#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

# prepare a temporary file beside the installed script.
target="${HOME:?}/.local/bin/tabs"
command -v tmux >/dev/null || { echo 'tabs needs tmux 3.0+' >&2; exit 1; }
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
trap 'rm -f "$tmp"' EXIT

# download and validate the script before installing it.
curl -fsSL https://raw.githubusercontent.com/sueszli/tmux-tabs/master/tmux-tabs.sh -o "$tmp"
bash -n "$tmp"
chmod +x "$tmp"
# keep the existing script when it is already current.
if cmp -s "$tmp" "$target" && [ -x "$target" ]; then
    echo "tabs is already up to date at $target"
    exit
fi
# replace the installed script with the validated download.
mv "$tmp" "$target"
echo "installed tabs at $target"
