#!/usr/bin/env bash
set -euo pipefail

url=https://raw.githubusercontent.com/sueszli/tmux-tabs/master/tmux-tabs.sh
bin_dir=${HOME:?}/.local/bin
target=$bin_dir/tabs

if ! command -v tmux >/dev/null 2>&1; then
    echo 'tabs needs tmux 3.0 or newer.' >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo 'Installing tabs needs curl.' >&2
    exit 1
fi

mkdir -p "$bin_dir"
tmp=$(mktemp "$bin_dir/.tabs.XXXXXX")
trap 'rm -f "$tmp"' EXIT

curl -fsSL "$url" -o "$tmp"
bash -n "$tmp"
chmod 755 "$tmp"

if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
    echo "tabs is already up to date at $target"
    exit 0
fi

mv -f "$tmp" "$target"
echo "Installed tabs at $target"

case :$PATH: in
    *:"$bin_dir":*) ;;
    *) echo "Add $bin_dir to your PATH to run tabs." ;;
esac
