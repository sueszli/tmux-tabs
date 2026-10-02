#!/usr/bin/env bats

load test_helper

@test "sourcing the script has no tmux or installation side effects" {
    run bash -c 'source "$1"' bash "$PROJECT_ROOT/tmux-tabs.sh"
    assert_success
    assert_output ''
    [ ! -s "$TMUX_CALLS" ]
    [ ! -d "$HOME/.claude" ]
}

@test "JSON hooks preserve settings and unrelated hooks, and back up the original" {
    printf '%s\n' '{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo keep"}]}]}}' >"$HOME/settings.json"
    cp "$HOME/settings.json" "$BATS_TEST_TMPDIR/original"

    run install_json_hooks
    assert_success
    run jq -e '.theme == "dark" and .hooks.Stop[0].hooks[0].command == "echo keep" and (.hooks.Stop | length) == 2 and .hooks.SessionStart[0].matcher == "startup|resume"' "$HOME/settings.json"
    assert_success
    run cmp "$BATS_TEST_TMPDIR/original" "$HOME/settings.json.before-tabs"
    assert_success
}

@test "JSON hook installation is idempotent and does not overwrite backups" {
    printf '{"theme":"dark"}\n' >"$HOME/settings.json"
    run install_json_hooks
    assert_success
    cp "$HOME/settings.json" "$BATS_TEST_TMPDIR/installed"
    cp "$HOME/settings.json.before-tabs" "$BATS_TEST_TMPDIR/backup"

    run install_json_hooks
    assert_success
    assert_output ''
    run cmp "$BATS_TEST_TMPDIR/installed" "$HOME/settings.json"
    assert_success
    run cmp "$BATS_TEST_TMPDIR/backup" "$HOME/settings.json.before-tabs"
    assert_success
}

@test "invalid JSON and invalid hook structures leave the original untouched" {
    local invalid
    for invalid in '{broken' '[]' '{"hooks":[]}' '{"hooks":{"Stop":{}}}'; do
        printf '%s\n' "$invalid" >"$HOME/settings.json"
        cp "$HOME/settings.json" "$BATS_TEST_TMPDIR/original"
        run install_json_hooks
        assert_failure
        run cmp "$BATS_TEST_TMPDIR/original" "$HOME/settings.json"
        assert_success
        [ ! -e "$HOME/settings.json.before-tabs" ]
        run find "$HOME" -type f
        assert_output "$HOME/settings.json"
    done
}

@test "legacy hooks are replaced while unrelated commands remain" {
    printf '%s\n' '{"hooks":{"Stop":[{"hooks":[{"command":"/old/tabs-agent-hook claude Stop"},{"command":"echo keep"}]}]}}' >"$HOME/settings.json"
    run install_json_hooks
    assert_success
    run jq -e '[.hooks.Stop[].hooks[].command] | length == 2 and index("echo keep") != null and index("/old/tabs-agent-hook claude Stop") == null' "$HOME/settings.json"
    assert_success
}

@test "full installation creates Claude, Codex, and Pi hooks in the sandbox" {
    run tabs_install_hooks
    assert_success
    run jq -e '.hooks.SessionStart[0].hooks[0].command | contains("tabs_agent_hook claude SessionStart")' "$HOME/.claude/settings.json"
    assert_success
    run jq -e '.hooks.Stop[0].hooks[0].command | contains("tabs_agent_hook codex Stop")' "$HOME/.codex/hooks.json"
    assert_success
    run grep -F 'pi.on("agent_settled"' "$PI_CODING_AGENT_DIR/extensions/tmux-tabs.js"
    assert_success
    [ ! -s "$TMUX_CALLS" ]

    run tabs_install_hooks
    assert_success
    assert_output ''
}

@test "Pi extension paths expand a literal tilde from the environment" {
    # shellcheck disable=SC2088,SC2016 # literal tilde; expansion in child bash.
    run env PI_CODING_AGENT_DIR='~/custom-agent' bash -c \
        'source "$1"; tabs_install_pi_hooks "$1"' bash "$PROJECT_ROOT/tmux-tabs.sh"
    assert_success
    [ -f "$HOME/custom-agent/extensions/tmux-tabs.js" ]
}

@test "Pi extension installation preserves and backs up an existing extension" {
    mkdir -p "$PI_CODING_AGENT_DIR/extensions"
    printf '// original\n' >"$PI_CODING_AGENT_DIR/extensions/tmux-tabs.js"
    run tabs_install_pi_hooks "$PROJECT_ROOT/tmux-tabs.sh"
    assert_success
    run grep -Fx '// original' "$PI_CODING_AGENT_DIR/extensions/tmux-tabs.js.before-tabs"
    assert_success
    run tabs_install_pi_hooks "$PROJECT_ROOT/tmux-tabs.sh"
    assert_success
    assert_output ''
}
