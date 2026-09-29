#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/shim" "$tmp/real"
cp "$repo/tmux-tabs.sh" "$tmp/shim/tabs"
ln -s tabs "$tmp/shim/codex"
cat > "$tmp/real/codex" <<'MOCK'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
MOCK
chmod +x "$tmp/real/codex"
export PATH="$tmp/shim:$tmp/real:$PATH"

run() { "$tmp/shim/codex" "$@"; }
assert_output() {
    local expected=$1 actual
    shift
    actual=$(run "$@")
    [ "$actual" = "$expected" ] || {
        printf 'expected: %s\nactual: %s\n' "$expected" "$actual" >&2
        exit 1
    }
}

unset TMUX TMUX_PANE
assert_output '<--yolo>' --yolo
export TMUX='/tmp/tmux-501/other,123,0' TMUX_PANE='%1'
assert_output '<--yolo>' --yolo
export TMUX='/tmp/tmux-501/tabs,123,0'
assert_output $'<--no-daemon>\n<--yolo>' --yolo
assert_output $'<--no-daemon>\n<resume>\n<--last>' resume --last
assert_output $'<--no-daemon>\n<--yolo>' --no-daemon --yolo
assert_output $'<exec>\n<echo hi>' exec 'echo hi'
assert_output $'<--remote>\n<ws://localhost:3000>' --remote ws://localhost:3000

mkdir "$tmp/home" "$tmp/bin"
cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$TABS_REPO/tmux-tabs.sh" "$2"; exit; fi
    shift
done
exit 1
MOCK
cat > "$tmp/bin/tmux" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$tmp/bin/curl" "$tmp/bin/tmux"
HOME="$tmp/home" TABS_REPO="$repo" PATH="$tmp/bin:$PATH" bash "$repo/install.sh" >/dev/null 2>&1
[ -L "$tmp/home/.local/bin/codex" ]
[ "$tmp/home/.local/bin/codex" -ef "$tmp/home/.local/bin/tabs" ]

echo 'Codex shim tests passed'
