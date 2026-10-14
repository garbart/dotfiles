#!/usr/bin/env bash
#
# Dotfiles installer: zsh + Starship for macOS and Linux (apt, dnf, yum).
#
#   curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | bash
#
# The repo is cloned into ~/.local/share/dotfiles and configs are symlinked
# from there. Nothing is written to the current directory or to temp files.
# Run the same command again to update.
#
# Overrides:
#   DOTFILES_REPO    git URL to clone   (default: https://github.com/garbart/dotfiles.git)
#   DOTFILES_BRANCH  branch to use      (default: main)
#   DOTFILES_DIR     where to clone     (default: ~/.local/share/dotfiles)
#
# Running ./install.sh from a checkout links that checkout instead of cloning.
#
# The script only defines functions until the last line, so a truncated
# download fails to parse instead of running half an install.

set -euo pipefail

: "${HOME:?HOME is not set}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/garbart/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
BACKUP_DIR="$HOME/.local/state/dotfiles/backups/$(date +%Y%m%d-%H%M%S)"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
OS_NAME="$(uname -s)"
USER_NAME="$(id -un)"
SUDO_KEEPALIVE_PID=""

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'Warning: %s\n' "$*" >&2
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

cleanup() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}

# Ask for the sudo password once and keep the timestamp fresh until we exit,
# so long steps (Homebrew, package installs) don't prompt again halfway.
ensure_sudo() {
    [ "$(id -u)" != "0" ] || return 0
    [ -z "$SUDO_KEEPALIVE_PID" ] || return 0

    command_exists sudo || die "sudo is required (or run as root)"
    log "Requesting sudo access"
    sudo -v || die "sudo access is required"

    while kill -0 "$$" 2>/dev/null; do
        sudo -n true
        sleep 30
    done >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}

as_root() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        ensure_sudo
        sudo "$@"
    fi
}

# Download a script into memory and run it with an interpreter, no temp file.
run_remote_script() {
    local url="$1" interpreter="$2" script
    shift 2

    script="$(curl -fsSL "$url")" || die "failed to download $url"
    "$interpreter" -c "$script" "$interpreter" "$@" </dev/null
}

preflight() {
    case "$OS_NAME" in
        Darwin)
            [ "$(id -u)" != "0" ] || die "run as a regular user on macOS; the script asks for sudo when needed"
            ;;
        Linux) ;;
        *) die "OS '$OS_NAME' is not supported. Supported: macOS, Linux (apt, dnf, yum)" ;;
    esac

    # Catches `sudo bash` keeping the caller's HOME: everything would end up
    # owned by root inside someone else's home.
    [ -O "$HOME" ] || die "$HOME is not owned by $USER_NAME; run the installer as the user you are setting up, without sudo"
}

# --- Dependencies ------------------------------------------------------------

load_homebrew_env() {
    local brew_bin

    for brew_bin in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -n "$brew_bin" ] && [ -x "$brew_bin" ]; then
            eval "$("$brew_bin" shellenv)"
            return 0
        fi
    done

    return 1
}

install_homebrew() {
    if load_homebrew_env; then
        return
    fi

    log "Installing Homebrew"
    # NONINTERACTIVE Homebrew relies on an already cached sudo timestamp.
    ensure_sudo
    NONINTERACTIVE=1 run_remote_script https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh /bin/bash

    load_homebrew_env || die "Homebrew was installed, but brew was not found"
}

install_linux_packages() {
    local cmd missing=()

    # Only missing commands are installed: Rocky ships curl-minimal, which
    # conflicts with the curl package. tar and gzip are for the Starship installer.
    for cmd in curl git zsh tar gzip; do
        command_exists "$cmd" || missing+=("$cmd")
    done

    [ "${#missing[@]}" -gt 0 ] || return 0

    log "Installing ${missing[*]}"
    if command_exists apt-get; then
        as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates "${missing[@]}"
    elif command_exists dnf; then
        as_root dnf install -y -q ca-certificates "${missing[@]}"
    elif command_exists yum; then
        as_root yum install -y -q ca-certificates "${missing[@]}"
    else
        die "no supported package manager found (apt-get, dnf, yum)"
    fi
}

install_dependencies() {
    case "$OS_NAME" in
        Darwin) install_homebrew ;;
        Linux) install_linux_packages ;;
    esac
}

install_starship() {
    if command_exists starship || [ -x "$HOME/.local/bin/starship" ]; then
        return
    fi

    log "Installing Starship"
    case "$OS_NAME" in
        Darwin)
            brew install starship
            ;;
        Linux)
            mkdir -p "$HOME/.local/bin"
            run_remote_script https://starship.rs/install.sh sh --yes --bin-dir "$HOME/.local/bin"
            ;;
    esac
}

# --- Repository --------------------------------------------------------------

# Prints the checkout directory when the script runs from a file inside one.
local_checkout_dir() {
    local dir

    [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ] || return 1
    dir="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd -P)"
    [ -f "$dir/zsh/zshrc" ] && [ -f "$dir/starship/config" ] || return 1
    printf '%s\n' "$dir"
}

sync_repo() {
    local local_dir

    if local_dir="$(local_checkout_dir)"; then
        DOTFILES_DIR="$local_dir"
        log "Using local checkout $DOTFILES_DIR"
        return
    fi

    if [ ! -e "$DOTFILES_DIR" ]; then
        log "Cloning $DOTFILES_REPO ($DOTFILES_BRANCH) into $DOTFILES_DIR"
        mkdir -p "$(dirname "$DOTFILES_DIR")"
        git clone --quiet --branch "$DOTFILES_BRANCH" "$DOTFILES_REPO" "$DOTFILES_DIR"
        return
    fi

    [ -d "$DOTFILES_DIR/.git" ] || die "$DOTFILES_DIR exists but is not a git repository"

    if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain)" ]; then
        warn "$DOTFILES_DIR has local changes, skipping update"
        return
    fi

    log "Updating $DOTFILES_DIR ($DOTFILES_BRANCH)"
    git -C "$DOTFILES_DIR" fetch --quiet --prune origin
    git -C "$DOTFILES_DIR" checkout --quiet "$DOTFILES_BRANCH" 2>/dev/null \
        || git -C "$DOTFILES_DIR" checkout --quiet -b "$DOTFILES_BRANCH" "origin/$DOTFILES_BRANCH"
    git -C "$DOTFILES_DIR" merge --quiet --ff-only "origin/$DOTFILES_BRANCH" \
        || die "cannot fast-forward $DOTFILES_DIR to origin/$DOTFILES_BRANCH; resolve it manually"
}

# --- Configs -----------------------------------------------------------------

# Symlink src to dst. Existing files are moved to BACKUP_DIR, never deleted;
# existing symlinks are just replaced.
link() {
    local src="$1" dst="$2" backup

    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        return
    fi

    if [ -L "$dst" ]; then
        rm -f "$dst"
    elif [ -e "$dst" ]; then
        backup="$BACKUP_DIR/${dst#"$HOME"/}"
        mkdir -p "$(dirname "$backup")"
        mv "$dst" "$backup"
        warn "moved existing $dst to $backup"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
    log "Linked $dst"
}

link_configs() {
    link "$DOTFILES_DIR/starship/config" "$HOME/.config/starship.toml"
    link "$DOTFILES_DIR/zsh/zshrc" "$HOME/.config/zsh/zshrc"
}

# Keep the user's ~/.zshrc and only append a line that sources ours.
install_zsh_loader() {
    local zshrc="$HOME/.zshrc"
    local loader='source "$HOME/.config/zsh/zshrc"'

    if [ -f "$zshrc" ] && grep -qxF "$loader" "$zshrc"; then
        return
    fi

    {
        printf '\n# >>> dotfiles zsh setup >>>\n'
        printf '%s\n' "$loader"
        printf '# <<< dotfiles zsh setup <<<\n'
    } >>"$zshrc"
    log "Added dotfiles loader to $zshrc"
}

# --- Login shell -------------------------------------------------------------

login_shell() {
    case "$OS_NAME" in
        Darwin) dscl . -read "/Users/$USER_NAME" UserShell 2>/dev/null | awk '{print $2}' ;;
        Linux) getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f7 ;;
    esac
}

set_login_shell() {
    local zsh_path

    case "$(login_shell)" in
        */zsh) return ;;
    esac

    zsh_path="$(command -v zsh)" || die "zsh was not found"

    if [ -r /etc/shells ] && ! grep -qxF "$zsh_path" /etc/shells; then
        printf '%s\n' "$zsh_path" | as_root tee -a /etc/shells >/dev/null
    fi

    log "Changing login shell to $zsh_path"
    if command_exists chsh; then
        as_root chsh -s "$zsh_path" "$USER_NAME"
    elif [ "$OS_NAME" = "Linux" ]; then
        as_root usermod -s "$zsh_path" "$USER_NAME"
    else
        warn "chsh not found; login shell was not changed"
    fi
}

main() {
    trap cleanup EXIT

    preflight
    install_dependencies
    sync_repo
    install_starship
    link_configs
    install_zsh_loader
    set_login_shell

    log "Done. Restart the terminal or run: exec zsh"
}

main "$@"
