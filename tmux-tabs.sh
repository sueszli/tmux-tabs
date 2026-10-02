#!/usr/bin/env bash

#
# hook installation
#

tabs_finish_hook_file() {
    # preserve backups and avoid replacing unchanged hook files
    local staged=$1 path=$2 agent=$3
    if [ -f "$path" ] && cmp -s "$staged" "$path"; then
        rm "$staged"
        return 0
    fi
    if [ -f "$path" ] && [ ! -e "${path}.before-tabs" ]; then
        cp -p "$path" "${path}.before-tabs"
    fi
    mv "$staged" "$path"
    printf 'hooks: %s %s\n' "$agent" "$path"
}

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
    ' <<<"$original" >"$staged"; then
        rm "$staged"
        return 1
    fi
    tabs_finish_hook_file "$staged" "$path" "$agent"
}

tabs_install_pi_hooks() {
    # pi discovers javascript extensions in its agent directory
    local self=$1 path staged
    path=${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}
    # match literal tildes from the environment, then expand them ourselves.
    # shellcheck disable=SC2088
    case $path in
        \~) path=$HOME ;;
        \~/*) path=$HOME/${path#\~/} ;;
    esac
    path=$path/extensions/tmux-tabs.js
    mkdir -p "${path%/*}"
    staged=$(mktemp "${path}.XXXXXX") || return 1
    if [ -f "$path" ]; then
        cp -p "$path" "$staged" || {
            rm "$staged"
            return 1
        }
    fi
    {
        printf 'const hook = %s;\n' "$(jq -n --arg path "$self" '$path')"
        cat <<'JS'

export default function (pi) {
    if (!process.env.TMUX?.split(",")[0].endsWith("/tabs") || !process.env.TMUX_PANE) return;

    async function update(event, ctx) {
        if (ctx.mode !== "tui") return;
        try {
            await pi.exec("bash", ["-c", 'source "$1"; tabs_agent_hook pi "$2"',
                "tmux-tabs", hook, event], { timeout: 3000 });
        } catch {
            // status updates must not interrupt the agent.
        }
    }

    pi.on("session_start", (_event, ctx) => update("SessionStart", ctx));
    pi.on("agent_start", (_event, ctx) => update("UserPromptSubmit", ctx));
    // agent_end can precede retries, compaction and queued follow-ups.
    pi.on("agent_settled", (_event, ctx) => update("Stop", ctx));
    pi.on("session_shutdown", (_event, ctx) => update("SessionEnd", ctx));
}
JS
    } >"$staged"
    tabs_finish_hook_file "$staged" "$path" pi
}

tabs_install_hooks() (
    # configure user hooks for claude code, codex cli and pi
    set -euo pipefail
    command -v jq >/dev/null || {
        echo 'jq required' >&2
        exit 1
    }
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
    local codex_event_names=(SessionStart UserPromptSubmit PermissionRequest PostToolUse Stop Interrupt SessionEnd)
    codex_events=$(jq -n --args '
        $ARGS.positional | map([., (if . == "SessionStart" then "startup|resume" else null end), .])
    ' "${codex_event_names[@]}")

    json=$HOME/.claude/settings.json
    tabs_install_json_hooks "$json" claude "$claude_events" "$prefix" "$old"

    config=$HOME/.codex/config.toml
    json=$HOME/.codex/hooks.json
    if [ -f "$config" ] && grep -Eq '^[[:space:]]*\[\[?hooks([.][A-Z]|\])' "$config"; then
        if ! grep -Fq 'tabs_agent_hook codex SessionStart' "$config" || grep -Eq '^# [[:upper:]]+ tabs-agent-status$' "$config"; then
            [ -e "${config}.before-tabs" ] || cp -p "$config" "${config}.before-tabs"
            staged=$(mktemp "${config}.XXXXXX")
            cp -p "$config" "$staged"
            if grep -Eqi '^# begin tabs-agent-status$' "$config"; then
                sed '/^# [Bb][Ee][Gg][Ii][Nn] tabs-agent-status$/,/^# [Ee][Nn][Dd] tabs-agent-status$/d' "$config" >"$staged"
            fi
            {
                printf '\n# begin tabs-agent-status\n'
                for event in "${codex_event_names[@]}"; do
                    printf '[[hooks.%s]]\n' "$event"
                    [ "$event" != SessionStart ] || printf 'matcher = "startup|resume"\n'
                    printf 'hooks = [{ type = "command", command = %s, timeout = 3 }]\n\n' "$(jq -n --arg command "$prefix codex $event'" '$command')"
                done
                printf '# end tabs-agent-status\n'
            } >>"$staged"
            mv "$staged" "$config"
            printf 'hooks: codex %s\n' "$config"
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
            ' "$json" >"$staged"
            if jq -e 'keys == ["hooks"] and ([.hooks[][]?] | length) == 0' "$staged" >/dev/null; then
                rm "$staged" "$json"
            else
                mv "$staged" "$json"
            fi
        fi
    else
        tabs_install_json_hooks "$json" codex "$codex_events" "$prefix" "$old"
    fi

    tabs_install_pi_hooks "$self"
)

#
# agent status
#

tabs_agent_hook() {
    # update pane state and color tabs waiting for input
    local agent event style window windows
    if [ "${1:-}" != refresh ]; then
        if [[ ${TMUX%%,*} != */tabs || -z ${TMUX_PANE:-} ]]; then
            printf '{}\n'
            return 0
        fi

        agent=${1:-}
        event=${2:-}
        case $agent in claude | codex | pi) ;; *) return 1 ;; esac

        case $event in
            SessionEnd)
                tmux -L tabs set-option -p -u -t "$TMUX_PANE" @tabs_agent >/dev/null 2>&1
                tmux -L tabs set-option -p -u -t "$TMUX_PANE" @tabs_state >/dev/null 2>&1
                ;;
            SessionStart)
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state idle >/dev/null 2>&1
                ;;
            Stop | StopFailure | Interrupt | PermissionRequest | PreQuestion)
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state feedback >/dev/null 2>&1
                ;;
            UserPromptSubmit | PostToolUse | PostToolUseFailure | PostQuestion)
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_agent "$agent" >/dev/null 2>&1
                tmux -L tabs set-option -p -t "$TMUX_PANE" @tabs_state working >/dev/null 2>&1
                ;;
            *) return 1 ;;
        esac
    fi

    if [ "${1:-}" = refresh ]; then
        # restore base styles when tmux reloads the tab configuration
        tmux -L tabs set-option -g status-style 'bg=colour236,fg=colour245' >/dev/null 2>&1
        tmux -L tabs set-option -g status-left-style default >/dev/null 2>&1
        tmux -L tabs set-option -g status-right-style default >/dev/null 2>&1
        tmux -L tabs set-option -gw window-status-style default >/dev/null 2>&1
        tmux -L tabs set-option -gw window-status-current-style 'bg=colour250,fg=colour236,bold' >/dev/null 2>&1
        tmux -L tabs set-option -gw window-status-last-style default >/dev/null 2>&1
        tmux -L tabs set-option -gw window-status-activity-style reverse >/dev/null 2>&1
        tmux -L tabs set-option -gw window-status-bell-style reverse >/dev/null 2>&1
        windows=$(tmux -L tabs list-windows -a -F '#{window_id}' 2>/dev/null)
    else
        # a hook can only change the window containing its pane
        windows=$(tmux -L tabs display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)
        [ -n "$windows" ] || windows=$(tmux -L tabs list-windows -a -F '#{window_id}' 2>/dev/null)
    fi

    while IFS= read -r window; do
        [ -n "$window" ] || continue
        if grep -qx feedback < <(tmux -L tabs list-panes -t "$window" -F '#{@tabs_state}' 2>/dev/null); then
            for style in window-status-style window-status-last-style window-status-activity-style window-status-bell-style; do
                tmux -L tabs set-option -w -t "$window" "$style" 'bg=colour34,fg=colour232' >/dev/null 2>&1
            done
            tmux -L tabs set-option -w -t "$window" window-status-current-style 'bg=colour34,fg=colour232,bold' >/dev/null 2>&1
        else
            for style in window-status-style window-status-current-style window-status-last-style window-status-activity-style window-status-bell-style; do
                tmux -L tabs set-option -wu -t "$window" "$style" >/dev/null 2>&1
            done
        fi
    done <<<"$windows"
    tmux -L tabs refresh-client >/dev/null 2>&1 || true
    # codex stop requires json and claude code accepts the same empty response
    printf '{}\n'
}

#
# tab display
#

resize() (
    # resync terminal size after ssh misses a resize
    tty=$(tmux display -p -t "${TMUX_PANE:-}" '#{client_tty}') || exit 1
    [ -e "$tty" ] || exit 1

    # serialize terminal size queries
    lock=${TMPDIR:-/tmp}/tabs-resize-$(id -u).lock
    mkdir "$lock" 2>/dev/null || exit 0
    trap 'rmdir "$lock" 2>/dev/null' EXIT INT TERM

    exec </dev/tty
    saved=$(stty -g) || exit 1
    stty raw -echo

    # query terminal size through tmux
    printf '\033Ptmux;\033\033[18t\033\134' >/dev/tty
    IFS= read -r -d t -t 3.0 reply
    stty "$saved"

    rows=${reply#*'[8;'}
    rows=${rows%%;*}
    cols=${reply##*;}
    case $rows$cols in *[!0-9]* | '') exit 1 ;; esac

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
    if [ "$state" = working ] && [ $(($(date +%s) % 2)) -eq 1 ]; then
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

    file=$(mktemp "${TMPDIR:-/tmp}/tabs-conf.XXXXXX") || return 1
    tmux_config >"$file"
    tmux -L tabs source-file "$file" || {
        rm -f "$file"
        return 1
    }
    rm -f "$file"
    tabs_agent_hook refresh >/dev/null

    # query terminal size only from a shell
    pane_cmd=$(tmux -L tabs display-message -p -t "$pane" '#{pane_current_command}') || return 0
    case $pane_cmd in
        *sh) tmux -L tabs send-keys -t "$pane" " env BASH_ENV=${BASH_SOURCE[0]} bash -c resize >/dev/null 2>&1; clear" Enter ;;
    esac

    tmux -L tabs refresh-client
}

#
# shared agent rules
#

tabs_sync_rules() (
    set -euo pipefail
    local source_file=${XDG_CONFIG_HOME:-$HOME/.config}/agents/AGENTS.md
    local dry_run=0 migrate=0 path staged i bundled=''
    local -a paths stages
    stages=()
    trap 'for staged in "${stages[@]}"; do rm -f "$staged"; done; [ -z "$bundled" ] || rm -f "$bundled"' EXIT
    if [ ! -e "$source_file" ]; then
        bundled=$(mktemp "${TMPDIR:-/tmp}/tabs-policy.XXXXXX")
        source_file=$bundled
        cat > "$bundled" <<'POLICY'
# Git, GitHub and GitLab workflow approvals

Read-only Git, gh and glab commands, fetching, and non-destructive local
staging and commits do not require confirmation.

Before remote writes, obtain one approval for a clearly scoped workflow,
identifying the changes, remote, branch and intended actions. An explicit
user request to push or create a PR/MR authorizes the corresponding workflow,
including staging, committing, a normal push and creating that PR/MR.
Approval covers retries of the same operation, not unrelated remote writes.
Ask again if the scope, remote or branch changes.

Require separate explicit approval for force-pushing, deleting remote
resources, merging PRs/MRs, publishing releases, changing permissions,
secrets or CI settings, and destructive local operations that discard work.
Apply these rules equally to git, gh, glab, API clients and scripts.
Do not bypass approval by switching tools. Never expose credentials.

These are agent instructions, not an enforced CLI security boundary.
POLICY
    fi
    while [ "$#" -gt 0 ]; do
        case $1 in
            --dry-run) dry_run=1 ;;
            --migrate-git-rules) migrate=1 ;;
            --help)
                printf 'Usage: tabs sync-rules [--dry-run] [--migrate-git-rules] [FILE]\n'
                return 0 ;;
            --*) echo "Unknown option: $1" >&2; return 1 ;;
            *) source_file=$1 ;;
        esac
        shift
    done
    [ -s "$source_file" ] && [ -f "$source_file" ] || {
        echo "Create a nonempty shared policy first: $source_file" >&2
        return 1
    }
    if grep -Eq '^<!-- (BEGIN|END) (TMUX-TABS SHARED RULES|USER GIT APPROVAL RULES) -->$' "$source_file"; then
        echo 'Shared policy must not contain managed-section markers' >&2
        return 1
    fi
    paths=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
           "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
           "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/AGENTS.md")
    # Render and validate every destination before changing any instruction file.
    for path in "${paths[@]}"; do
        if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
            echo "Refusing symlink or non-regular destination: $path" >&2
            return 1
        fi
        staged=$(mktemp "${TMPDIR:-/tmp}/tabs-rules.XXXXXX")
        stages+=("$staged")
        awk -v policy="$source_file" -v migrate="$migrate" '
            function emit( line) {
                print "<!-- BEGIN TMUX-TABS SHARED RULES -->"
                while ((getline line < policy) > 0) print line
                close(policy)
                print "<!-- END TMUX-TABS SHARED RULES -->"
            }
            /^<!-- BEGIN (TMUX-TABS SHARED RULES|USER GIT APPROVAL RULES) -->$/ {
                if (inside || seen++) { bad=1; exit 1 }
                if ($0 ~ /USER GIT/ && !migrate) { bad=1; exit 1 }
                expected=$0; sub(/BEGIN/, "END", expected)
                inside=1; emit(); next
            }
            /^<!-- END (TMUX-TABS SHARED RULES|USER GIT APPROVAL RULES) -->$/ {
                if (!inside || $0 != expected) { bad=1; exit 1 }
                inside=0; next
            }
            !inside { print }
            END {
                if (bad || inside) exit 1
                if (!seen) { if (NR) print ""; emit() }
            }
        ' "$(if [ -f "$path" ]; then printf '%s' "$path"; else printf /dev/null; fi)" > "$staged" || {
            echo "Invalid/duplicate markers in $path, or legacy rules require --migrate-git-rules" >&2
            return 1
        }
    done
    for i in "${!paths[@]}"; do
        path=${paths[$i]}
        staged=${stages[$i]}
        if [ -f "$path" ] && cmp -s "$path" "$staged"; then continue; fi
        if [ "$dry_run" = 1 ]; then
            diff -u "$(if [ -f "$path" ]; then printf '%s' "$path"; else printf /dev/null; fi)" "$staged" || [ "$?" = 1 ]
            printf 'would sync: %s\n' "$path"
            continue
        fi
        mkdir -p "${path%/*}"
        if [ -f "$path" ]; then
            [ -e "${path}.before-tabs-rules" ] || cp -p "$path" "${path}.before-tabs-rules"
        fi
        # Stage beside the destination for an atomic rename, preserving its mode.
        local adjacent
        adjacent=$(mktemp "${path}.XXXXXX")
        stages+=("$adjacent")
        if [ -f "$path" ]; then cp -p "$path" "$adjacent"; fi
        cp "$staged" "$adjacent"
        mv "$adjacent" "$path"
        printf 'rules: %s\n' "$path"
    done
)


#
# entry point
#

# tmux callbacks source the functions from this file
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "${0##*/}" != codex ]; then
        if [ "${1:-}" = sync-rules ]; then
            shift
            tabs_sync_rules "$@"
            exit $?
        fi
        exec tmux -L tabs -f <(tmux_config) new-session -A -s tabs
    fi
    real=''
    while IFS= read -r candidate; do
        if [ ! "$candidate" -ef "$0" ]; then
            real=$candidate
            break
        fi
    done < <(type -a -p codex)
    [ -n "$real" ] || {
        echo 'codex not found' >&2
        exit 127
    }
    for arg in "$@"; do
        case $arg in
            --) break ;;
            --no-daemon | --remote | --remote=*) exec "$real" "$@" ;;
        esac
    done
    case ${1:-} in
        agents | exec | e | review | login | logout | mcp | plugin | app-server | remote-control | app | completion | update | doctor | sandbox | debug | apply | cloud | queue | archive | delete | unarchive | migrate-rollouts)
            exec "$real" "$@"
            ;;
    esac
    if [[ ${TMUX:-} == */tabs,* && -n ${TMUX_PANE:-} ]]; then
        exec "$real" --no-daemon "$@"
    fi
    exec "$real" "$@"
fi
