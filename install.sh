#!/usr/bin/env bash
PS4='+${LINENO}: '
set -euox pipefail

#
# setup
#

target="${HOME:?}/.local/bin/tabs"
command -v tmux >/dev/null
command -v jq >/dev/null
# pin both downloads to one revision
revision=${TABS_REVISION:-$(curl -fsSL https://api.github.com/repos/sueszli/tmux-tabs/commits/master | jq -er '.sha')}
[[ $revision =~ ^[0-9a-f]{40}$ ]]
base_url="https://raw.githubusercontent.com/sueszli/tmux-tabs/$revision"
mkdir -p "${target%/*}"
tmp=$(mktemp "${target}.XXXXXX")
module_dir="$HOME/.local/share/tmux-tabs"
mkdir -p "$module_dir"
module_tmp=$(mktemp "$module_dir/guardrails.XXXXXX")
trap 'rm -f "$tmp" "$module_tmp"' EXIT

configure_telegram() (
    set +x
    local config=${XDG_CONFIG_HOME:-$HOME/.config}/tmux-tabs/telegram token chat_id
    [[ ! -e $config && ! -L $config ]] || return 0
    { exec 3<>/dev/tty; } 2>/dev/null || return 0

    printf 'telegram bot token from @BotFather (enter to skip): ' >&3
    IFS= read -rs token <&3 || return 0
    printf '\n' >&3
    umask 077
    set -C
    if [ -z "$token" ]; then
        mkdir -p "${config%/*}" && : >"$config"
        return
    fi
    [[ $token =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || return 0

    printf 'send any message to your bot in telegram, then press enter\n' >&3
    read -r <&3 || return 0
    if ! chat_id=$(curl -q -fs -m 10 -K <(printf 'url = "https://api.telegram.org/bot%s/getUpdates"\n' "$token") |
        jq -r '.result | map(select(.message.chat.id)) | max_by(.update_id) | .message.chat.id') ||
        [[ ! $chat_id =~ ^-?[0-9]+$ ]]; then
        printf 'no telegram chat found\n' >&2
        return 0
    fi
    curl -q -fsS -m 10 -K <(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token") \
        --data-urlencode "chat_id=$chat_id" --data-urlencode 'text=tabs notifications enabled' >/dev/null &&
        mkdir -p "${config%/*}" && printf '%s\n' "$token" "$chat_id" >"$config" &&
        printf 'telegram notifications enabled\n'
)

#
# installation
#

curl -fsSL "$base_url/tmux-tabs.sh" -o "$tmp"
curl -fsSL "$base_url/guardrails.sh" -o "$module_tmp"
bash -n "$tmp"
bash -n "$module_tmp"
chmod +x "$tmp"
mv "$module_tmp" "$module_dir/guardrails.sh"
if ! cmp -s "$tmp" "$target" || [ ! -x "$target" ]; then
    mv "$tmp" "$target"
fi
BASH_ENV="$target" bash -c tabs_install_hooks
configure_telegram || true

# install global rules on every install/update
bash "$module_dir/guardrails.sh"

#
# codex shim
#

for shim in "${target%/*}/codex" "$HOME/bin/codex"; do
    [ -d "${shim%/*}" ] || continue
    if [ ! -e "$shim" ] && [ ! -L "$shim" ]; then
        ln -s "$target" "$shim"
    fi
done

case ${SHELL:-} in
    */zsh | zsh) rcs=("${ZDOTDIR:-$HOME}/.zshrc") ;;
    */bash | bash)
        for rc in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
            [ ! -f "$rc" ] || break
        done
        rcs=("$HOME/.bashrc" "$rc")
        ;;
    *) exit 0 ;;
esac
shim=$module_dir/codex
[ "$shim" -ef "$target" ] || ln -s "$target" "$shim"
printf -v quoted '%q' "$shim"
printf -v alias_command 'alias codex=%q' "$quoted"
for rc in "${rcs[@]}"; do
    if ! grep -Fxq "$alias_command" "$rc" 2>/dev/null; then
        [ ! -f "$rc" ] || [ -e "$rc.before-tabs" ] || cp -p "$rc" "$rc.before-tabs"
        printf '\n%s\n' "$alias_command" >>"$rc"
    fi
done
