#!/usr/bin/env bats

load test_helper

@test "agent hooks do nothing outside the tabs server or without a pane" {
    export TMUX=/tmp/test/default,123,0
    run tabs_agent_hook claude Stop
    assert_success
    assert_output '{}'
    [ ! -s "$TMUX_CALLS" ]

    export TMUX=/tmp/test/tabs,123,0
    unset TMUX_PANE
    run tabs_agent_hook claude Stop
    assert_success
    assert_output '{}'
    [ ! -s "$TMUX_CALLS" ]
}

@test "unknown agents and events are rejected before calling tmux" {
    run tabs_agent_hook unknown Stop
    assert_failure
    run tabs_agent_hook claude UnknownEvent
    assert_failure
    [ ! -s "$TMUX_CALLS" ]
}

@test "session start sets the agent and idle state" {
    run tabs_agent_hook pi SessionStart
    assert_success
    assert_output '{}'
    run grep -Fx -- '-L tabs set-option -p -t %7 @tabs_agent pi' "$TMUX_CALLS"
    assert_success
    run grep -Fx -- '-L tabs set-option -p -t %7 @tabs_state idle' "$TMUX_CALLS"
    assert_success
}

@test "prompt and tool completion events mark the pane working" {
    local event
    for event in UserPromptSubmit PostToolUse PostToolUseFailure PostQuestion; do
        : >"$TMUX_CALLS"
        run tabs_agent_hook codex "$event"
        assert_success
        assert_output '{}'
        run grep -Fx -- '-L tabs set-option -p -t %7 @tabs_state working' "$TMUX_CALLS"
        assert_success
    done
}

@test "attention events mark the pane waiting for feedback" {
    local event
    for event in Stop StopFailure Interrupt PermissionRequest PreQuestion; do
        : >"$TMUX_CALLS"
        run tabs_agent_hook claude "$event"
        assert_success
        assert_output '{}'
        run grep -Fx -- '-L tabs set-option -p -t %7 @tabs_state feedback' "$TMUX_CALLS"
        assert_success
    done
}

@test "session end clears both pane options" {
    run tabs_agent_hook pi SessionEnd
    assert_success
    run grep -Fx -- '-L tabs set-option -p -u -t %7 @tabs_agent' "$TMUX_CALLS"
    assert_success
    run grep -Fx -- '-L tabs set-option -p -u -t %7 @tabs_state' "$TMUX_CALLS"
    assert_success
}

@test "feedback from any pane highlights its window" {
    export TMUX_STATES=$'working\nfeedback\nidle'
    run tabs_agent_hook claude Stop
    assert_success
    run grep -Fx -- '-L tabs set-option -w -t @1 window-status-style bg=colour34,fg=colour232' "$TMUX_CALLS"
    assert_success
    run grep -Fx -- '-L tabs set-option -w -t @1 window-status-current-style bg=colour34,fg=colour232,bold' "$TMUX_CALLS"
    assert_success
}

@test "windows without feedback have their local styles cleared" {
    run tabs_agent_hook claude UserPromptSubmit
    assert_success
    run grep -Fx -- '-L tabs set-option -wu -t @1 window-status-current-style' "$TMUX_CALLS"
    assert_success
}

@test "refresh restores base styles and enumerates all windows" {
    run tabs_agent_hook refresh
    assert_success
    assert_output '{}'
    run grep -Fx -- '-L tabs set-option -g status-style bg=colour236,fg=colour245' "$TMUX_CALLS"
    assert_success
    run grep -Fx -- '-L tabs list-windows -a -F #{window_id}' "$TMUX_CALLS"
    assert_success
}
