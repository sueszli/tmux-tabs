#!/usr/bin/env bash
#
# shared agent rules
#

tabs_sync_rules() (
    set -euo pipefail
    local source_file=${XDG_CONFIG_HOME:-$HOME/.config}/agents/AGENTS.md
    local dry_run=0 path staged i bundled='' committed=0 complete=0
    local -a paths stages replacements originals
    stages=() replacements=() originals=()
    # shellcheck disable=SC2329
    cleanup() {
        local status=$? j
        trap - EXIT
        if [ "$complete" = 0 ]; then
            for ((j = committed - 1; j >= 0; j--)); do
                [ -n "${replacements[$j]}" ] || continue
                if [ -n "${originals[$j]}" ]; then
                    if ! mv -f "${originals[$j]}" "${paths[$j]}"; then
                        echo "Rollback failed; recover ${paths[$j]} from ${originals[$j]}" >&2
                        # retain recovery files
                        exit 1
                    fi
                else
                    rm -f "${paths[$j]}" || exit 1
                fi
            done
        fi
        for staged in "${stages[@]}"; do rm -f "$staged"; done
        [ -z "$bundled" ] || rm -f "$bundled"
        exit "$status"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [ ! -e "$source_file" ]; then
        bundled=$(mktemp "${TMPDIR:-/tmp}/tabs-policy.XXXXXX")
        source_file=$bundled
        cat >"$bundled" <<'POLICY'
# Git, GitHub and GitLab workflow approvals

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

These are agent instructions, not an enforced CLI security boundary.
POLICY
    fi
    while [ "$#" -gt 0 ]; do
        case $1 in
            --dry-run) dry_run=1 ;;
            --migrate-git-rules) : ;; # compatibility: migration is now automatic
            --help)
                printf 'Usage: tabs sync-rules [--dry-run] [FILE]\n'
                return 0
                ;;
            --*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
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
    # validate all destinations before writing
    for path in "${paths[@]}"; do
        if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
            echo "Refusing symlink or non-regular destination: $path" >&2
            return 1
        fi
        staged=$(mktemp "${TMPDIR:-/tmp}/tabs-rules.XXXXXX")
        stages+=("$staged")
        awk -v policy="$source_file" '
            function emit( line) {
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
        ' "$(if [ -f "$path" ]; then printf '%s' "$path"; else printf /dev/null; fi)" >"$staged" || {
            echo "Invalid/duplicate managed guardrail markers in $path" >&2
            return 1
        }
    done
    # stage replacements and rollback copies
    for i in "${!paths[@]}"; do
        path=${paths[$i]}
        staged=${stages[$i]}
        replacements[i]=''
        originals[i]=''
        if [ -f "$path" ] && cmp -s "$path" "$staged"; then continue; fi
        if [ "$dry_run" = 1 ]; then
            diff -u "$(if [ -f "$path" ]; then printf '%s' "$path"; else printf /dev/null; fi)" "$staged" || [ "$?" = 1 ]
            printf 'would sync: %s\n' "$path"
            continue
        fi
        mkdir -p "${path%/*}"
        local adjacent original backup="${path}.before-tabs-rules"
        if [ -L "$backup" ] || { [ -e "$backup" ] && [ ! -f "$backup" ]; }; then
            echo "Refusing symlink or non-regular backup: $backup" >&2
            return 1
        fi
        if [ -f "$path" ]; then
            original=$(mktemp "${path}.rollback.XXXXXX")
            stages+=("$original")
            cp -p "$path" "$original"
            originals[i]=$original
            [ -e "$backup" ] || cp -p "$path" "$backup"
        fi
        # same-filesystem rename, preserving mode
        adjacent=$(mktemp "${path}.XXXXXX")
        stages+=("$adjacent")
        if [ -f "$path" ]; then cp -p "$path" "$adjacent"; fi
        cp "$staged" "$adjacent"
        replacements[i]=$adjacent
    done
    for i in "${!paths[@]}"; do
        # include failed renames in rollback
        committed=$((i + 1))
        [ -n "${replacements[$i]}" ] || continue
        mv -f "${replacements[$i]}" "${paths[$i]}"
    done
    complete=1
    for i in "${!paths[@]}"; do
        [ -z "${replacements[$i]}" ] || printf 'rules: %s\n' "${paths[$i]}"
    done
)

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    tabs_sync_rules "$@"
fi
