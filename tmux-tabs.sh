#!/usr/bin/env bash

tabs_install_json_hooks() {
    # merge agent hooks into json settings while preserving existing hooks
    local path=$1 agent=$2 events=$3 prefix=$4 old=$5 staged original
    mkdir -p "${path%/*}"
    staged=$(mktemp "${path}.XXXXXX") || return 1
    if [ -f "$path" ]; then
        original=$(<"$path")
        cp -p "$path" "$staged" || return 1
    else
        original='{}'
    fi
    if ! jq --arg agent "$agent" --arg prefix "$prefix" --arg old "$old" --argjson events "$events" '
        if type != "object" then error("settings must be a JSON object") else . end
        | .hooks //= {}
        | if (.hooks | type) != "object" then error("hooks must be a JSON object") else . end
        | reduce $events[] as $event (.;
            .hooks[$event[0]] //= []
            | if (.hooks[$event[0]] | type) != "array" then error("hook event must be a JSON array") else . end
            | .hooks[$event[0]] |= map(
                .hooks |= map(select(
                    (.command // "") as $command
                    | (($command | gsub("\\\\"; "") | contains($old))
                       and ($command | endswith(" " + $agent + " " + $event[2]))) | not
                ))
                | select(.hooks | length > 0)
              )
            | ($prefix + " " + $agent + " " + $event[2] + "\u0027") as $command
            | if ([.hooks[$event[0]][]? | .hooks[]? | select(.command == $command)] | length) > 0
              then .
              else .hooks[$event[0]] += [
                ({hooks: [{type: "command", command: $command, timeout: 3}]}
                 + (if $event[1] == null then {} else {matcher: $event[1]} end))
              ]
              end
          )
    ' <<< "$original" > "$staged"; then
        rm "$staged"
        return 1
    fi
    if [ -f "$path" ] && cmp -s "$staged" "$path"; then
        rm "$staged"
        return 0
    fi
    if [ -f "$path" ] && [ ! -e "${path}.before-tabs" ]; then
        cp -p "$path" "${path}.before-tabs"
    fi
    mv "$staged" "$path"
    printf 'configured %s status hooks in %s\n' "$agent" "$path"
}

tabs_install_hooks() (
    # configure user hooks for claude code and codex cli
    set -euo pipefail
    command -v jq >/dev/null || { echo 'agent status setup needs jq' >&2; exit 1; }
    local self quoted old prefix claude_events codex_events config json event staged
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
    printf -v quoted '%q' "$self"
    old=${self}-agent-hook
    prefix="BASH_ENV=$quoted bash -c 'tabs_agent_hook"
    claude_events='[
      ["SessionStart", "startup|resume", "SessionStart"],
      ["UserPromptSubmit", null, "UserPromptSubmit"],
      ["PermissionRequest", null, "PermissionRequest"],
      ["Notification", "^(permission_prompt|idle_prompt)$", "PermissionRequest"],
      ["PreToolUse", "^AskUserQuestion$", "PreQuestion"],
      ["Elicitation", null, "PreQuestion"],
      ["ElicitationResult", null, "PostQuestion"],
      ["PostToolUse", null, "PostToolUse"],
      ["PostToolUseFailure", null, "PostToolUseFailure"],
      ["Stop", null, "Stop"],
      ["StopFailure", null, "StopFailure"],
      ["SessionEnd", null, "SessionEnd"]
    ]'
    codex_events='[
      ["SessionStart", "startup|resume", "SessionStart"],
      ["UserPromptSubmit", null, "UserPromptSubmit"],
      ["PermissionRequest", null, "PermissionRequest"],
      ["PostToolUse", null, "PostToolUse"],
      ["Stop", null, "Stop"],
      ["Interrupt", null, "Interrupt"],
      ["SessionEnd", null, "SessionEnd"]
    ]'

    json=$HOME/.claude/settings.json
    tabs_install_json_hooks "$json" claude "$claude_events" "$prefix" "$old"

    config=$HOME/.codex/config.toml
    json=$HOME/.codex/hooks.json
    if [ -f "$config" ] && grep -Eq '^[[:space:]]*\[\[?hooks([.]|\])' "$config"; then
        if ! grep -Fq 'tabs_agent_hook codex SessionStart' "$config" || grep -Eq '^# [[:upper:]]+ tabs-agent-status$' "$config"; then
            [ -e "${config}.before-tabs" ] || cp -p "$config" "${config}.before-tabs"
            staged=$(mktemp "${config}.XXXXXX")
            cp -p "$config" "$staged"
            if grep -Eqi '^# begin tabs-agent-status$' "$config"; then
                sed '/^# [Bb][Ee][Gg][Ii][Nn] tabs-agent-status$/,/^# [Ee][Nn][Dd] tabs-agent-status$/d' "$config" > "$staged"
            fi
            {
                printf '\n# begin tabs-agent-status\n'
                for event in SessionStart UserPromptSubmit PermissionRequest PostToolUse Stop Interrupt SessionEnd; do
                    printf '[[hooks.%s]]\n' "$event"
                    [ "$event" != SessionStart ] || printf 'matcher = "startup|resume"\n'
                    printf 'hooks = [{ type = "command", command = %s, timeout = 3 }]\n\n' "$(jq -n --arg command "$prefix codex $event'" '$command')"
                done
                printf '# end tabs-agent-status\n'
            } >> "$staged"
            mv "$staged" "$config"
            printf 'configured codex status hooks in %s\n' "$config"
        fi
        # migrate old tabs hooks stored beside inline codex hooks
        if [ -f "$json" ] && jq -e --arg old "$old" '
            any(.hooks[][]?.hooks[]?;
                (.command // "") as $command
                | ($command | gsub("\\\\"; "") | contains($old)) and ($command | contains(" codex ")))
        ' "$json" >/dev/null; then
            staged=$(mktemp "${json}.XXXXXX")
            cp -p "$json" "$staged"
            jq --arg old "$old" '
                .hooks |= with_entries(.value |= map(
                    .hooks |= map(select(
                        (.command // "") as $command
                        | (($command | gsub("\\\\"; "") | contains($old)) and ($command | contains(" codex "))) | not
                    ))
                    | select(.hooks | length > 0)
                ))
            ' "$json" > "$staged"
            if jq -e 'keys == ["hooks"] and ([.hooks[][]?] | length) == 0' "$staged" >/dev/null; then
                rm "$staged" "$json"
            else
                mv "$staged" "$json"
            fi
        fi
    else
        tabs_install_json_hooks "$json" codex "$codex_events" "$prefix" "$old"
    fi
)

tabs_agent_hook() {
    # update pane state and color tabs waiting for input
    local agent event attention state style window
    if [ "${1:-}" != refresh ]; then
        case ${TMUX%%,*} in */tabs) ;; *) printf '{}\n'; return 0 ;; esac
        [ -n "${TMUX_PANE:-}" ] || { printf '{}\n'; return 0; }

        agent=${1:-}
        event=${2:-}
        case $agent in claude|codex) ;; *) return 1 ;; esac

        case $event in
        SessionEnd)
            tmux -L tabs set-option -p -u -t "$TMUX_PANE" @tabs_agent >/dev/null 2>&1
            tmux -L tabs set-option -p -u -t "$TMUX_PANE" @tabs_state >/dev/null 2>&1
            ;;
        SessionStart)
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state idle >/dev/null 2>&1
            ;;
        Stop|StopFailure|Interrupt|PermissionRequest|PreQuestion)
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state feedback >/dev/null 2>&1
            ;;
        UserPromptSubmit|PostToolUse|PostToolUseFailure|PostQuestion)
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
            tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state working >/dev/null 2>&1
            ;;
            *) return 1 ;;
        esac
    fi

    # keep the bar neutral and color only tabs waiting for input
    tmux -L tabs set-option -g status-style 'bg=colour236,fg=colour245' >/dev/null 2>&1
    tmux -L tabs set-option -g status-left-style default >/dev/null 2>&1
    tmux -L tabs set-option -g status-right-style default >/dev/null 2>&1
    tmux -L tabs set-option -gw window-status-style default >/dev/null 2>&1
    tmux -L tabs set-option -gw window-status-current-style 'bg=colour250,fg=colour236,bold' >/dev/null 2>&1
    tmux -L tabs set-option -gw window-status-last-style default >/dev/null 2>&1
    tmux -L tabs set-option -gw window-status-activity-style reverse >/dev/null 2>&1
    tmux -L tabs set-option -gw window-status-bell-style reverse >/dev/null 2>&1

    while IFS= read -r window; do
        attention=0
        while IFS= read -r state; do
            if [ "$state" = feedback ]; then
                attention=1
                break
            fi
        done < <(tmux -L tabs list-panes -t "$window" -F '#{@tabs_state}' 2>/dev/null)

        if [ "$attention" = 1 ]; then
            for style in window-status-style window-status-last-style window-status-activity-style window-status-bell-style; do
                tmux -L tabs set-option -w -t "$window" "$style" 'bg=colour34,fg=colour232' >/dev/null 2>&1
            done
            tmux -L tabs set-option -w -t "$window" window-status-current-style 'bg=colour34,fg=colour232,bold' >/dev/null 2>&1
        else
            for style in window-status-style window-status-current-style window-status-last-style window-status-activity-style window-status-bell-style; do
                tmux -L tabs set-option -wu -t "$window" "$style" >/dev/null 2>&1
            done
        fi
    done < <(tmux -L tabs list-windows -a -F '#{window_id}' 2>/dev/null)
    tmux -L tabs refresh-client >/dev/null 2>&1 || true
    # codex stop requires json and claude code accepts the same empty response
    printf '{}\n'
}

resize() (
    # resync terminal size after ssh misses a resize
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}') || exit 1
    [ -e "$tty" ] || exit 1

    # serialize terminal size queries
    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    # read the reply without echo
    exec < /dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo

    # query terminal size through tmux
    printf '\ePtmux;\e\e[18t\e\\' > /dev/tty
    IFS= read -r -d t -t 3 reply
    stty "$saved"

    # parse rows and columns
    rows=${reply#*'[8;'}
    rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]*|'') exit 1 ;; esac

    # update the client tty
    stty -F "$tty" columns "$cols" rows "$rows" 2>/dev/null || stty -f "$tty" columns "$cols" rows "$rows" 2>/dev/null || exit 1
    tmux refresh-client
    exit 0
)

tab_label() {
    # show the program name behind a node launcher
    local root=$1 fallback=$2 pane=$3 agent state marker
    agent=$(tmux -L tabs show-option -p -v -t "$pane" @tabs_agent 2>/dev/null)
    state=$(tmux -L tabs show-option -p -v -t "$pane" @tabs_state 2>/dev/null)
    if [ -z "$agent" ]; then
        agent=$(ps -e -o pid=,ppid=,comm= | awk -v root="$root" -v fallback="$fallback" '
        { parent[$1] = $2; command[$1] = $3 }
        END {

            # find programs descended from the pane shell
            for (pid in parent) {
                current = pid
                while (current != root && current in parent) current = parent[current]
                if (current == root && command[pid] ~ /(^|\/)(codex|claude)$/) {
                    sub(/^.*\//, "", command[pid])
                    print command[pid]
                    exit
                }
            }
            print fallback
        }
    ')
    fi
    marker='•'
    if [ "$state" = working ] && [ $(( $(date +%s) % 2 )) -eq 1 ]; then
        marker=' '
    fi
    printf '%s %s\n' "$marker" "$agent"
}

tmux_config() {
    # print the config for the tabs server
    local self
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")

    cat <<CONF
set -g prefix None
set -g base-index 1
set -g renumber-windows on
setw -g automatic-rename on
set -g allow-passthrough on

# tab bar
set -g status-position top
set -g status-interval 1
set -g status-style 'bg=colour236,fg=colour245'
set -g window-status-current-style 'bg=colour250,fg=colour236,bold'
set -g status-left ''
set -g status-right ' ^T shell  ^W close  ^← ^→ switch '
set -g window-status-format ' #(BASH_ENV=$self bash -c "tab_label #{pane_pid} #{pane_current_command} #{pane_id}") '
set -g window-status-current-format ' #(BASH_ENV=$self bash -c "tab_label #{pane_pid} #{pane_current_command} #{pane_id}") '

# tab keys
bind -n C-t new-window -c '#{pane_current_path}'
bind -n C-n new-window -c '#{pane_current_path}'
bind -n C-w kill-window
bind -n C-Right next-window
bind -n C-Left previous-window
bind -n C-f next-window
bind -n C-b previous-window

# redraw after opening or switching tabs
set-hook -g after-select-window "run-shell -b \"BASH_ENV=$self bash -c 'render #{pane_id}'\""
set-hook -g after-new-window "run-shell -b \"BASH_ENV=$self bash -c 'render #{pane_id}'\""
CONF
}

render() {
    # reload config, correct shell size and redraw tab labels
    local pane=$1 pane_cmd file

    # load the latest installed config
    file=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || return 1
    tmux_config > "$file"
    tmux -L tabs source-file "$file" || { rm -f "$file"; return 1; }
    rm -f "$file"
    tabs_agent_hook refresh >/dev/null

    # query terminal size only from a shell
    pane_cmd=$(tmux -L tabs display-message -p -t "$pane" '#{pane_current_command}') || return 0
    case $pane_cmd in
        *sh) tmux -L tabs send-keys -t "$pane" " env BASH_ENV=${BASH_SOURCE[0]} bash -c resize >/dev/null 2>&1; clear" Enter ;;
    esac

    # refresh every tab label
    tmux -L tabs refresh-client
}

tabs_hosts() {
    # list the candidate hosts for a new session, one per line
    local config=${TABS_HOSTS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/tabs/hosts}
    {
        if [ -n "${TABS_HOSTS:-}" ]; then
            printf '%s\n' "$TABS_HOSTS"
        elif [ -r "$config" ]; then
            cat "$config"
        fi
    } | awk '{ sub(/#.*/, ""); gsub(/,/, " "); for (i = 1; i <= NF; i++) print $i }'
}

tabs_is_self() {
    # succeed when a host name refers to this machine
    local host=$1 self
    self=$(hostname) || return 1
    [ "$host" = "$self" ] || [ "${host%%.*}" = "${self%%.*}" ]
}

tabs_loadavg_command() {
    # print a shell snippet reporting the one minute load average
    printf '%s' \
        'if [ -r /proc/loadavg ]; then read -r l _ < /proc/loadavg;' \
        ' else l=$(uptime | sed "s/.*load averages*:[[:space:]]*//; s/,.*//; s/[[:space:]].*//"); fi;' \
        ' printf "%s\n" "$l"'
}

tabs_probe() {
    # print "<load average> <host>" when a host answers in time
    local host=$1 command load
    command=$(tabs_loadavg_command)
    if tabs_is_self "$host"; then
        load=$(sh -c "$command" 2>/dev/null)
    else
        load=$(ssh -o BatchMode=yes -o ConnectTimeout="${TABS_TIMEOUT:-5}" \
            -o StrictHostKeyChecking=accept-new "$host" "$command" 2>/dev/null)
    fi
    # an unreachable host reports nothing and drops out of the ranking
    case $load in '' | *[!0-9.]*) return 0 ;; esac
    printf '%s %s\n' "$load" "$host"
}

tabs_pick_host() {
    # print the reachable candidate host carrying the lowest load average
    local hosts dir host index=0
    hosts=$(tabs_hosts)
    [ -n "$hosts" ] || return 0
    dir=$(mktemp -d "${TMPDIR:-/tmp}/tabs-probe.XXXXXX") || return 1
    # probe every candidate at once so one slow host cannot hold up the rest
    while IFS= read -r host; do
        index=$((index + 1))
        tabs_probe "$host" > "$dir/$index" &
    done <<< "$hosts"
    wait
    cat "$dir"/* 2>/dev/null | sort -g | awk 'NR == 1 { print $2 }'
    rm -rf "$dir"
}

tabs_host_file() {
    # print the path recording which host holds the session
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/tabs/host"
}

tabs_remember() {
    # record the host holding the session so later calls reconnect to it
    local host=$1 file staged
    file=$(tabs_host_file)
    mkdir -p "${file%/*}" || return 1
    staged=$(mktemp "${file}.XXXXXX") || return 1
    printf '%s\n' "$host" > "$staged" && mv -f "$staged" "$file" && return 0
    rm -f "$staged"
    return 1
}

tabs_recall() {
    # print the host that last held a session
    local file host
    file=$(tabs_host_file)
    [ -r "$file" ] || return 1
    IFS= read -r host < "$file" || return 1
    case $host in '' | *[!a-zA-Z0-9._-]*) return 1 ;; esac
    printf '%s\n' "$host"
}

tabs_session_on() {
    # succeed when a host already runs a tabs session
    local host=$1
    if tabs_is_self "$host"; then
        tmux -L tabs has-session -t '=tabs' 2>/dev/null
    else
        ssh -o BatchMode=yes -o ConnectTimeout="${TABS_TIMEOUT:-5}" "$host" \
            'bash -l -c "tmux -L tabs has-session -t =tabs"' >/dev/null 2>&1
    fi
}

tabs_scan() {
    # print a candidate host already running a session, if any
    local hosts dir host index=0
    hosts=$(tabs_hosts)
    [ -n "$hosts" ] || return 0
    dir=$(mktemp -d "${TMPDIR:-/tmp}/tabs-scan.XXXXXX") || return 1
    while IFS= read -r host; do
        index=$((index + 1))
        { tabs_session_on "$host" && printf '%s\n' "$host"; } > "$dir/$index" 2>/dev/null &
    done <<< "$hosts"
    wait
    cat "$dir"/* 2>/dev/null | awk 'NF { print; exit }'
    rm -rf "$dir"
}

tabs_connect() {
    # hand this terminal to the tabs session on another host
    local host=$1 self command status
    self=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")
    # ssh joins arguments into shell text, so quote the remote call as one word
    printf -v command '%q --local' "$self"
    printf -v command 'bash -l -c %q' "$command"
    printf 'tabs: connecting to %s\n' "$host" >&2
    ssh -t "$host" "$command"
    status=$?
    [ "$status" = 0 ] || printf 'tabs: %s exited with status %s; run tabs --local to stay here.\n' \
        "$host" "$status" >&2
    return "$status"
}

tabs_attach() {
    # attach on this machine, creating the session when it is missing
    local config
    local -a scope=()
    tabs_remember "$(hostname)"
    if ! tmux -L tabs has-session -t '=tabs' 2>/dev/null; then
        # logind reaps leftover user processes when KillUserProcesses is on,
        # so the server needs its own scope to outlive the login that made it
        if command -v systemd-run >/dev/null 2>&1 &&
            systemd-run --scope --user --quiet true >/dev/null 2>&1; then
            scope=(systemd-run --scope --user --quiet)
        fi
        # a scope cannot inherit the /dev/fd path of a process substitution
        config=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || return 1
        tmux_config > "$config"
        "${scope[@]}" tmux -L tabs -f "$config" new-session -d -s tabs
        rm -f "$config"
    fi
    exec tmux -L tabs attach-session -t '=tabs'
}

tabs_main() {
    # attach to the session, choosing the least loaded host on first use
    local host

    case ${1-} in
        --local) tabs_attach ;;
        --pick) tabs_pick_host; return 0 ;;
        --help)
            printf '%s\n' \
                'usage: tabs [--local | --pick | --help]' \
                '' \
                'with no candidate hosts configured tabs runs on this machine.' \
                'list hosts in ~/.config/tabs/hosts or $TABS_HOSTS and the first' \
                'session starts on the reachable host with the lowest load average,' \
                'then reconnects there over ssh from anywhere.' \
                '' \
                '  --local  attach on this machine and remember it' \
                '  --pick   print the host that would be chosen' \
                '  --help   show this message'
            return 0 ;;
    esac

    # never nest a session inside itself
    case ${TMUX%%,*} in
        */tabs)
            printf 'tabs: already in the tabs session.\n' >&2
            printf 'press ctrl+t for a new tab and ctrl+left / ctrl+right to switch.\n' >&2
            return 0 ;;
    esac

    # a live session on this machine always wins over a remote one
    tmux -L tabs has-session -t '=tabs' 2>/dev/null && tabs_attach

    # reconnect to the remembered host for as long as its session lives
    if host=$(tabs_recall) && ! tabs_is_self "$host" && tabs_session_on "$host"; then
        tabs_connect "$host"
        return
    fi

    # the note can go stale, so never start a second session behind a live one
    host=$(tabs_scan)
    if [ -n "$host" ] && ! tabs_is_self "$host"; then
        tabs_remember "$host"
        tabs_connect "$host"
        return
    fi

    # first use: settle on the least loaded host that answers
    host=$(tabs_pick_host)
    if [ -n "$host" ] && ! tabs_is_self "$host"; then
        tabs_remember "$host"
        tabs_connect "$host"
        return
    fi
    tabs_attach
}

# tmux callbacks source the functions from this file
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    tabs_main "$@"
fi
