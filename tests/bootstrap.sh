#!/usr/bin/env bash
# install pinned test tools locally; no sudo or global packages required
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command -v git >/dev/null || {
    printf 'git required\n' >&2
    exit 1
}
mkdir -p "$root/.tools"

install_tool() {
    local name=$1 version=$2 revision=$3 destination
    destination=$root/.tools/$name
    if [ ! -d "$destination" ]; then
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" \
            "https://github.com/bats-core/$name.git" "$destination"
    fi
    if [ "$(git -C "$destination" rev-parse HEAD)" != "$revision" ]; then
        printf 'Unexpected revision for %s; remove %s and retry\n' "$name" "$destination" >&2
        return 1
    fi
}

install_tool bats-core v1.12.0 713504bc0224a19b3d7c7958c18dc07f64f54b44
install_tool bats-support v0.3.0 24a72e14349690bcbf7c151b9d2d1cdd32d36eb1
install_tool bats-assert v2.1.0 78fa631d1370562d2cd4a1390989e706158e7bf0
printf 'Test tools ready in %s/.tools\n' "$root"
