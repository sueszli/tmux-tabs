#!/usr/bin/env bash
set -euo pipefail

#
# shared policy
#

TABS_DEFAULT_POLICY='# Git, GitHub and GitLab workflow approvals

Read-only Git, gh and glab commands, fetching, and non-destructive local
staging and commits do not require confirmation.

Remote writes always require explicit user authorization for the scoped
workflow. An explicit request IS authorization: do not ask the user to
approve the same action again or approve each prerequisite separately.

"Push" or "commit and push" authorizes staging the relevant changes,
committing if needed, and a normal push to the intended remote and branch,
including setting its upstream. It does not by itself authorize a new PR/MR.
"Make a PR/MR" or "open a PR/MR" also authorizes creating a suitable local
branch if needed and creating the PR/MR.
"Push to PR/MR" or "update the PR/MR" authorizes committing and pushing to
its branch; if no PR/MR exists, creating one is included.
"Rebase" authorizes fetching the requested base, rebasing onto it, and
resolving conflicts without another approval question. Preserve unrelated
work. It does not authorize force-pushing or discarding work. An explicit
request for a higher-risk action is its separate approval; do not ask again.

Before an authorized remote write, briefly state what will be affected,
then proceed without another consent question. Ask a focused clarification
only if the relevant changes or destination are genuinely ambiguous.
A request to implement, fix, review or prepare work alone does not authorize
remote writes. Do not stage unrelated changes.

Approval covers safe retries of the same operation, not unrelated writes.
Check whether a non-idempotent write (such as PR/MR creation) succeeded
before retrying it. Ask again if scope, destination or risk changes.
Authorization ends when the requested workflow is completed or canceled;
it is not standing permission for future work.

Require separate explicit approval for force-pushing, deleting remote
resources, rewriting published history, merging or closing PRs/MRs,
publishing tags or releases, changing permissions,
secrets or CI settings, and destructive local operations that discard work.
Apply these rules equally to git, gh, glab, API clients and scripts.
Do not bypass approval by switching tools. Never expose credentials.

These are agent instructions, not an enforced CLI security boundary.'

# shellcheck disable=SC2016
TABS_RULES_RENDER='
    function emit( line, result) {
        print "<!-- BEGIN TMUX-TABS SHARED RULES -->"
        while ((result = getline line < policy) > 0) print line
        if (result < 0) { bad=1; exit 1 }
        close(policy)
        print "<!-- END TMUX-TABS SHARED RULES -->"
    }
    /^<!-- BEGIN (TMUX-TABS SHARED RULES|USER GIT APPROVAL RULES) -->$/ {
        if (inside || seen++) { bad=1; exit 1 }
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
'

#
# validation and rendering
#

tabs_rules_regular() {
    if [ -L "$1" ] || { [ -e "$1" ] && [ ! -f "$1" ]; }; then
        printf 'Refusing symlink or non-regular file: %s\n' "$1" >&2
        return 1
    fi
}

tabs_rules_policy() {
    [ -s "$1" ] && [ -f "$1" ] || {
        printf 'Create a nonempty shared policy first: %s\n' "$1" >&2
        return 1
    }
    if grep -Eq '^<!-- (BEGIN|END) (TMUX-TABS SHARED RULES|USER GIT APPROVAL RULES) -->$' "$1"; then
        printf '%s\n' 'Shared policy must not contain managed-section markers' >&2
        return 1
    fi
}

tabs_rules_render() {
    local input=/dev/null
    tabs_rules_regular "$2"
    [ ! -f "$2" ] || input=$2
    awk -v policy="$1" "$TABS_RULES_RENDER" "$input" >"$3" || {
        printf 'Invalid/duplicate managed guardrail markers in %s\n' "$2" >&2
        return 1
    }
}

#
# staging and recovery
#

tabs_rules_stage() {
    local path=$1 rendered=$2 record=$3 stage backup=${1}.before-tabs-rules
    mkdir -p "${path%/*}"
    tabs_rules_regular "$backup"
    stage=$(mktemp -d "${path}.tabs.XXXXXX")
    printf '%s\n' "$stage" >"$record"
    : >"$stage/new"
    chmod 600 "$stage/new"
    if [ -f "$path" ]; then
        cp -p "$path" "$stage/original"
        cp -p "$path" "$stage/new"
        [ -e "$backup" ] || cp -p "$path" "$backup"
    fi
    cp "$rendered" "$stage/new"
}

tabs_rules_restore() {
    if [ -f "$1/original" ]; then
        mv -f "$1/original" "$2" || {
            printf 'Rollback failed; recover %s from %s/original\n' "$2" "$1" >&2
            return 1
        }
    else
        rm -f "$2"
    fi
}

tabs_rules_cleanup() {
    local status=$1 workspace=$2 complete=$3 committed=$4 i stage
    shift 4
    local -a paths=("$@")
    trap - EXIT
    for ((i = ${#paths[@]} - 1; i >= 0; i--)); do
        [ -f "$workspace/$i.stage" ] || continue
        IFS= read -r stage <"$workspace/$i.stage"
        if [ "$complete" = 0 ] && [ "$i" -lt "$committed" ]; then
            tabs_rules_restore "$stage" "${paths[$i]}" || exit 1
        fi
        rm -rf "$stage"
    done
    rm -rf "$workspace"
    exit "$status"
}

#
# workflow
#

tabs_sync_rules() (
    local policy=${XDG_CONFIG_HOME:-$HOME/.config}/agents/AGENTS.md
    local dry_run=0 explicit=0 workspace i stage committed=0 complete=0
    local -a paths=("${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md"
        "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"
        "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/AGENTS.md")
    while [ "$#" -gt 0 ]; do
        case $1 in
            --dry-run) dry_run=1 ;;
            --migrate-git-rules) : ;; # legacy option
            --help)
                printf 'Usage: tabs sync-rules [--dry-run] [FILE]\n'
                return 0
                ;;
            --*)
                printf 'Unknown option: %s\n' "$1" >&2
                return 1
                ;;
            *)
                policy=$1
                explicit=1
                ;;
        esac
        shift
    done
    workspace=$(mktemp -d "${TMPDIR:-/tmp}/tabs-rules.XXXXXX")
    trap 'tabs_rules_cleanup "$?" "$workspace" "$complete" "$committed" "${paths[@]}"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [ ! -e "$policy" ]; then
        # only the default path may fall back to bundled rules
        [ "$explicit" = 0 ] || {
            printf 'Policy not found: %s\n' "$policy" >&2
            return 1
        }
        policy=$workspace/policy
        printf '%s\n' "$TABS_DEFAULT_POLICY" >"$policy"
    fi
    tabs_rules_policy "$policy"
    for i in "${!paths[@]}"; do
        tabs_rules_render "$policy" "${paths[$i]}" "$workspace/$i.rendered"
    done
    for i in "${!paths[@]}"; do
        if cmp -s "${paths[$i]}" "$workspace/$i.rendered"; then continue; fi
        if [ "$dry_run" = 1 ]; then
            local input=/dev/null
            [ ! -f "${paths[$i]}" ] || input=${paths[$i]}
            diff -u "$input" "$workspace/$i.rendered" || [ "$?" = 1 ]
            printf 'would sync: %s\n' "${paths[$i]}"
            continue
        fi
        tabs_rules_stage "${paths[$i]}" "$workspace/$i.rendered" "$workspace/$i.stage"
    done
    for i in "${!paths[@]}"; do
        [ -f "$workspace/$i.stage" ] || continue
        IFS= read -r stage <"$workspace/$i.stage"
        committed=$((i + 1))
        mv -f "$stage/new" "${paths[$i]}"
    done
    complete=1
)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    tabs_sync_rules "$@"
fi
