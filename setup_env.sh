#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_NAME="$(uname -s)"

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

brew_path() {
    if command_exists brew; then
        command -v brew
        return
    fi

    for path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$path" ]; then
            printf '%s\n' "$path"
            return
        fi
    done

    return 1
}

load_homebrew_env() {
    local brew_bin

    brew_bin="$(brew_path || true)"
    [ -n "$brew_bin" ] || return 1
    eval "$("$brew_bin" shellenv)"
}

real_home_for_user() {
    user="$1"

    case "$OS_NAME" in
        Darwin)
            dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | awk '{print $2}'
            ;;
        Linux)
            getent passwd "$user" 2>/dev/null | cut -d: -f6
            ;;
    esac
}

if [ -n "${SUDO_USER:-}" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="$(real_home_for_user "$REAL_USER")"
else
    REAL_USER="${USER:?USER is not set}"
    REAL_HOME="${HOME:?HOME is not set}"
fi

[ -n "$REAL_HOME" ] || die "could not detect home directory for $REAL_USER"

as_root() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_user() {
    if [ "$(id -u)" = "0" ]; then
        sudo -H -u "$REAL_USER" env HOME="$REAL_HOME" "$@"
    else
        env HOME="$REAL_HOME" "$@"
    fi
}

detect_linux_id() {
    [ -r /etc/os-release ] || die "Linux distribution is not supported: /etc/os-release not found"
    . /etc/os-release
    printf '%s\n' "${ID:-}"
}

install_linux_packages() {
    linux_id="$(detect_linux_id)"

    case "$linux_id" in
        ubuntu)
            as_root apt-get update
            as_root apt-get install -y ca-certificates curl gzip tar zsh
            ;;
        centos)
            if command_exists dnf; then
                as_root dnf install -y ca-certificates curl gzip tar util-linux-user zsh
            elif command_exists yum; then
                as_root yum install -y ca-certificates curl gzip tar util-linux-user zsh
            else
                die "CentOS requires dnf or yum"
            fi
            ;;
        *)
            die "Linux distribution '$linux_id' is not supported. Supported: Ubuntu, CentOS"
            ;;
    esac
}

install_homebrew() {
    local tmp_file

    [ "$OS_NAME" = "Darwin" ] || return

    if load_homebrew_env 2>/dev/null; then
        log "Homebrew already installed: $(command -v brew)"
        return
    fi

    command_exists curl || die "curl is required to install Homebrew"

    log "Installing Homebrew"
    tmp_file="$(mktemp)"
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$tmp_file"
    chmod +r "$tmp_file"
    as_user env NONINTERACTIVE=1 /bin/bash "$tmp_file"
    rm -f "$tmp_file"

    load_homebrew_env || die "Homebrew was installed, but brew was not found in the expected locations"
}

install_zsh() {
    case "$OS_NAME" in
        Darwin)
            install_homebrew
            if ! command_exists zsh; then
                as_user "$(brew_path)" install zsh
            fi
            ;;
        Linux)
            install_linux_packages
            ;;
        *)
            die "OS '$OS_NAME' is not supported. Supported: macOS, Ubuntu, CentOS"
            ;;
    esac
}

get_login_shell() {
    case "$OS_NAME" in
        Darwin)
            dscl . -read "/Users/$REAL_USER" UserShell 2>/dev/null | awk '{print $2}'
            ;;
        Linux)
            getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f7
            ;;
    esac
}

ensure_shell_is_allowed() {
    zsh_path="$1"

    if [ -r /etc/shells ] && grep -qxF "$zsh_path" /etc/shells; then
        return
    fi

    if [ "$OS_NAME" = "Darwin" ]; then
        printf '%s\n' "$zsh_path" | as_root tee -a /etc/shells >/dev/null
    fi
}

set_login_shell() {
    zsh_path="$(command -v zsh)"
    current_shell="$(get_login_shell)"

    if [ "$current_shell" = "$zsh_path" ]; then
        log "Login shell already set to $zsh_path"
        return
    fi

    ensure_shell_is_allowed "$zsh_path"

    if ! command_exists chsh; then
        log "chsh not found; zsh is installed, but login shell was not changed"
        return
    fi

    as_root chsh -s "$zsh_path" "$REAL_USER"
}

install_starship() {
    if command_exists starship; then
        log "Starship already installed: $(command -v starship)"
        return
    fi

    command_exists curl || die "curl is required to install Starship"

    tmp_file="$(mktemp)"
    curl -fsSL https://starship.rs/install.sh -o "$tmp_file"
    as_root sh "$tmp_file" --yes
    rm -f "$tmp_file"
}

link_configs() {
    as_user mkdir -p "$REAL_HOME/.config/zsh"
    as_user ln -sfn "$DOTFILES_DIR/starship/config" "$REAL_HOME/.config/starship.toml"
    as_user ln -sfn "$DOTFILES_DIR/zsh/zshrc" "$REAL_HOME/.config/zsh/zshrc"
}

install_zsh_loader() {
    as_user sh -c '
        set -e
        zshrc="$HOME/.zshrc"
        loader="source \"\$HOME/.config/zsh/zshrc\""

        touch "$zshrc"

        if grep -qxF "$loader" "$zshrc"; then
            exit 0
        fi

        {
            printf "\n# >>> dotfiles zsh setup >>>\n"
            printf "%s\n" "$loader"
            printf "# <<< dotfiles zsh setup <<<\n"
        } >> "$zshrc"
    '
}

install_zsh
set_login_shell
install_starship
link_configs
install_zsh_loader

log "Done. Restart the terminal or run: exec zsh"
