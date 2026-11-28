#!/usr/bin/env bash
# shared bats setup. keep all writes and external commands inside the sandbox
setup() {
    PROJECT_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
    load "$PROJECT_ROOT/.tools/bats-support/load.bash"
    load "$PROJECT_ROOT/.tools/bats-assert/load.bash"
    export HOME="$BATS_TEST_TMPDIR/home"
    export TMPDIR="$BATS_TEST_TMPDIR"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export PI_CODING_AGENT_DIR="$HOME/.pi/agent"
    export TMUX=/tmp/test/tabs,123,0 TMUX_PANE=%7
    export TMUX_CALLS="$BATS_TEST_TMPDIR/tmux-calls"
    export TMUX_STATES=idle TMUX_PREVIOUS_STATE=
    export CURL_LOG="$BATS_TEST_TMPDIR/curl"
    TELEGRAM_CONFIG=$XDG_CONFIG_HOME/tmux-tabs/telegram
    mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "${TELEGRAM_CONFIG%/*}"
    : >"$TMUX_CALLS"
    cp "$BATS_TEST_DIRNAME/tmux-stub.sh" "$BATS_TEST_TMPDIR/bin/tmux"
    cat >"$BATS_TEST_TMPDIR/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
[ ! -e /dev/fd/3 ]
printf '%s\n' "$@" >>"$CURL_LOG.args"
while [ "$1" != -K ]; do
    shift
done
cat "$2" >>"$CURL_LOG.config"
cat >>"$CURL_LOG.stdin"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/"{tmux,curl}
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    source "$PROJECT_ROOT/tmux-tabs.sh"
}

install_json_hooks() {
    tabs_install_json_hooks "$HOME/settings.json" claude \
        '[["SessionStart","startup|resume","SessionStart"],["Stop",null,"Stop"]]' \
        "BASH_ENV=/test/tabs bash -c 'tabs_agent_hook" /old/tabs-agent-hook
}

feedback_hook() {
    local previous_worker=${!:-}
    tabs_agent_hook claude PermissionRequest || return
    if [ "${!:-}" != "$previous_worker" ]; then
        wait "$!"
    fi
}
