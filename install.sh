#!/usr/bin/env bash
#
# Dotfiles installer: zsh, Starship and Neovim for macOS and Linux (apt, dnf, yum).
#
#   curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/refs/heads/master/install.sh | bash
#
# The repo is cloned into ~/.local/share/dotfiles and configs are symlinked
# from there. Nothing is written to the current directory or to temp files.
# Run the same command again to update.
#
# Overrides:
#   DOTFILES_REPO    git URL to clone   (default: https://github.com/garbart/dotfiles.git)
#   DOTFILES_BRANCH  branch to use      (default: master)
#   DOTFILES_DIR     where to clone     (default: ~/.local/share/dotfiles)
#
# Running ./install.sh from a checkout links that checkout instead of cloning.
#
# The Neovim config is not merged with an existing one: after confirmation the
# old config, plugins, state and cache are deleted and ours is linked instead.
#
# The script only defines functions until the last line, so a truncated
# download fails to parse instead of running half an install.

set -euo pipefail

: "${HOME:?HOME is not set}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/garbart/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-master}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.local/share/dotfiles}"
BACKUP_DIR="$HOME/.local/state/dotfiles/backups/$(date +%Y%m%d-%H%M%S)"
NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DIR="$HOME/.local/opt/nvim"
SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
LOCAL_CHECKOUT=""
OS_NAME="$(uname -s)"
USER_NAME="$(id -un)"
SUDO_KEEPALIVE_PID=""
STAGING_DIR=""
PARTIAL_FILE=""
NVIM_RESET=""
NVIM_LEFTOVERS=""

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
    if [ -n "$STAGING_DIR" ]; then
        rm -rf "$STAGING_DIR"
    fi
    if [ -n "$PARTIAL_FILE" ]; then
        rm -f "$PARTIAL_FILE"
    fi
}

# Ask for the sudo password once and keep the timestamp fresh until we exit,
# so long steps (Homebrew, package installs) don't prompt again halfway.
ensure_sudo() {
    [ "$(id -u)" != "0" ] || return 0
    [ -z "$SUDO_KEEPALIVE_PID" ] || return 0

    command_exists sudo || die "sudo is required (or run as root)"
    # Passwordless sudo, or a still valid timestamp, needs no password. Only
    # then ask: `sudo -v` asks even with passwordless sudo when some sudoers
    # rule for the user lacks NOPASSWD (e.g. the sudo group's).
    if ! sudo -n true 2>/dev/null; then
        log "Requesting sudo access"
        sudo -v || die "sudo access is required"
    fi

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
    local pair missing=()

    # Only missing commands are installed: Rocky ships curl-minimal, which
    # conflicts with the curl package. tar and gzip unpack downloads, cc builds
    # the tree-sitter parsers for nvim. Entries are command:package.
    for pair in curl:curl git:git zsh:zsh tar:tar gzip:gzip cc:gcc; do
        command_exists "${pair%%:*}" || missing+=("${pair#*:}")
    done

    [ "${#missing[@]}" -gt 0 ] || return 0
    install_packages ca-certificates "${missing[@]}"
}

install_packages() {
    log "Installing $*"
    if command_exists apt-get; then
        as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq
        as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
    elif command_exists dnf; then
        as_root dnf install -y -q "$@"
    elif command_exists yum; then
        as_root yum install -y -q "$@"
    else
        die "no supported package manager found (apt-get, dnf, yum)"
    fi
}

# Optional Linux packages (clangd, ImageMagick, librsvg) are installed only
# when that needs no password: as root, with passwordless sudo, or with sudo
# already unlocked for the required packages in this run. Otherwise, or when
# the install fails, a warning names the package to install by other means.
install_optional_package() {
    local name="$1" without="$2" apt_package="$3" dnf_package="$4" package

    if command_exists apt-get; then
        package="$apt_package"
    elif command_exists dnf; then
        package="$dnf_package"
    else
        warn "$name was not installed: $without"
        return 0
    fi

    if [ "$(id -u)" != "0" ] && ! sudo -n true 2>/dev/null; then
        warn "$name was not installed: it needs sudo (package $package); $without"
        return 0
    fi

    install_packages "$package" || warn "$name was not installed: $without"
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

# x86_64 or aarch64: the machines that have prebuilt Linux binaries.
linux_arch() {
    case "$(uname -m)" in
        x86_64) echo x86_64 ;;
        aarch64 | arm64) echo aarch64 ;;
        *) die "no prebuilt binaries for $(uname -m)" ;;
    esac
}

# The tag a GitHub repo's latest release redirects to.
latest_release() {
    local url

    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest")"
    printf '%s\n' "${url##*/}"
}

# Unpack into a staging dir first, so a failed download or a build that
# doesn't run here never replaces a working install.
install_neovim_linux() {
    local arch url

    arch="$(linux_arch)"
    [ "$arch" = x86_64 ] || arch=arm64
    url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-$arch.tar.gz"

    log "Installing Neovim from $url"
    STAGING_DIR="$NVIM_DIR.new"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    curl -fsSL "$url" | tar -xz -C "$STAGING_DIR" --strip-components=1
    "$STAGING_DIR/bin/nvim" --version >/dev/null \
        || die "downloaded Neovim does not run here (it needs glibc 2.35+)"

    rm -rf "$NVIM_DIR"
    mv "$STAGING_DIR" "$NVIM_DIR"
    STAGING_DIR=""
}

install_neovim() {
    case "$OS_NAME" in
        Darwin)
            if ! command_exists nvim; then
                log "Installing Neovim"
                brew install neovim
            fi
            ;;
        Linux)
            [ -x "$NVIM_DIR/bin/nvim" ] || install_neovim_linux
            mkdir -p "$HOME/.local/bin"
            ln -sfn "$NVIM_DIR/bin/nvim" "$HOME/.local/bin/nvim"
            ;;
    esac
}

# download_binary NAME URL UNPACK...: fetch URL, pipe it through UNPACK and
# save the result as ~/.local/bin/NAME. The command appears only once the
# download is complete; a failed one stops the script and cleanup() removes
# the partial file.
download_binary() {
    local name="$1" url="$2"
    shift 2

    log "Installing $name from $url"
    mkdir -p "$HOME/.local/bin"
    PARTIAL_FILE="$HOME/.local/bin/$name.part"
    curl -fsSL "$url" | "$@" >"$PARTIAL_FILE"
    chmod +x "$PARTIAL_FILE"
    mv "$PARTIAL_FILE" "$HOME/.local/bin/$name"
    PARTIAL_FILE=""
}

# nvim's search in files runs ripgrep, and its syntax parsers are built with
# the tree-sitter CLI. On Linux both are prebuilt binaries in ~/.local/bin,
# which works on any distro (Rocky has ripgrep only in EPEL).
install_editor_tools() {
    local arch version dir

    case "$OS_NAME" in
        Darwin)
            if ! command_exists rg; then
                log "Installing ripgrep"
                brew install ripgrep
            fi
            if ! command_exists tree-sitter; then
                log "Installing tree-sitter"
                brew install tree-sitter-cli
            fi
            ;;
        Linux)
            arch="$(linux_arch)"
            if ! command_exists rg && [ ! -x "$HOME/.local/bin/rg" ]; then
                version="$(latest_release BurntSushi/ripgrep)"
                dir="ripgrep-$version-$arch-unknown-linux-musl"
                download_binary rg \
                    "https://github.com/BurntSushi/ripgrep/releases/download/$version/$dir.tar.gz" \
                    tar -xzO "$dir/rg"
            fi
            if ! command_exists tree-sitter && [ ! -x "$HOME/.local/bin/tree-sitter" ]; then
                [ "$arch" = x86_64 ] && arch=x64 || arch=arm64
                download_binary tree-sitter \
                    "https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-$arch.gz" \
                    gunzip
            fi
            ;;
    esac
}

# install_opt NAME URL STRIP COMMAND...: unpack the release tarball URL
# (dropping STRIP leading path parts) into ~/.local/opt/NAME and link its
# bin/COMMANDs into ~/.local/bin. Unpacked into a staging dir first, so a
# failed download never replaces a working copy.
install_opt() {
    local name="$1" url="$2" strip="$3" dir="$HOME/.local/opt/$1" cmd
    shift 3

    log "Installing $name from $url"
    STAGING_DIR="$dir.new"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR" "$HOME/.local/bin"
    curl -fsSL "$url" | tar -xz -C "$STAGING_DIR" --strip-components="$strip"
    rm -rf "$dir"
    mv "$STAGING_DIR" "$dir"
    STAGING_DIR=""
    for cmd in "$@"; do
        ln -sfn "$dir/bin/$cmd" "$HOME/.local/bin/$cmd"
    done
}

# CMake 3.28+, which the projects' CMakePresets.json ask for.
cmake_is_recent() {
    local version major minor

    version="$(cmake --version 2>/dev/null | head -n1 | awk '{print $3}')"
    [ -n "$version" ] || return 1
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"
    [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -ge 28 ]; }
}

# C++: CMake and Conan to build in the shell, clangd for nvim's code
# navigation, completion and errors (see nvim/lua/config/lsp.lua). Only
# what's missing is installed. On Linux, CMake and Conan are their official
# builds in ~/.local/opt (distro CMake is often too old).
install_cpp_tools() {
    local arch version

    case "$OS_NAME" in
        Darwin)
            if ! command_exists cmake; then
                log "Installing CMake"
                brew install cmake
            fi
            if ! command_exists conan; then
                log "Installing Conan"
                brew install conan
            fi
            # clangd comes with the Command Line Tools, which Homebrew needs.
            ;;
        Linux)
            arch="$(linux_arch)"
            if ! cmake_is_recent && [ ! -x "$HOME/.local/opt/cmake/bin/cmake" ]; then
                version="$(latest_release Kitware/CMake)"
                install_opt cmake \
                    "https://github.com/Kitware/CMake/releases/download/$version/cmake-${version#v}-linux-$arch.tar.gz" \
                    1 cmake ctest cpack
            fi
            if ! command_exists conan && [ ! -x "$HOME/.local/opt/conan/bin/conan" ]; then
                version="$(latest_release conan-io/conan)"
                install_opt conan \
                    "https://github.com/conan-io/conan/releases/download/$version/conan-$version-linux-$arch.tgz" \
                    0 conan
            fi
            # clangd (Ubuntu names its package clangd, Rocky
            # clang-tools-extra), optional.
            if ! command_exists clangd; then
                install_optional_package clangd "no code navigation or completion in nvim" \
                    clangd clang-tools-extra
            fi
            ;;
    esac
}

# Python: basedpyright (Pyright, as in VSCode's Pylance) for nvim's code
# navigation, completion and errors (see nvim/lua/config/lsp.lua), installed
# by uv as a tool of its own, linked into ~/.local/bin. uv brings what it
# needs (a Python, and Node inside the basedpyright package), so this works
# on any distro; on Linux uv itself is its static build in ~/.local/bin.
# Optional: a failed install only warns.
install_python_tools() {
    local arch uv

    if ! command_exists uv && [ ! -x "$HOME/.local/bin/uv" ]; then
        case "$OS_NAME" in
            Darwin)
                log "Installing uv"
                brew install uv
                ;;
            Linux)
                arch="$(linux_arch)"
                download_binary uv \
                    "https://github.com/astral-sh/uv/releases/latest/download/uv-$arch-unknown-linux-musl.tar.gz" \
                    tar -xzO "uv-$arch-unknown-linux-musl/uv"
                ;;
        esac
    fi
    if ! command_exists basedpyright-langserver && [ ! -x "$HOME/.local/bin/basedpyright-langserver" ]; then
        log "Installing basedpyright"
        uv="$(command -v uv || echo "$HOME/.local/bin/uv")"
        "$uv" tool install basedpyright ||
            warn "basedpyright failed to install: no Python code navigation in nvim"
    fi
}

# The nvim file tree (and the Starship git icon) draw Nerd Font glyphs. On
# Linux the font comes from whatever machine the terminal runs on.
install_nerd_font() {
    local cask=font-jetbrains-mono-nerd-font

    [ "$OS_NAME" = "Darwin" ] || return 0
    brew list --cask "$cask" >/dev/null 2>&1 && return 0

    log "Installing JetBrains Mono Nerd Font"
    brew install --cask "$cask"
    log "Select \"JetBrainsMono Nerd Font Mono\" as the font in your terminal settings"
}

# The terminal to run nvim in: it draws images (kitty graphics protocol) and
# has Nerd Font icons built in. A copy installed by hand is left alone.
install_ghostty() {
    [ "$OS_NAME" = "Darwin" ] || return 0
    [ -d /Applications/Ghostty.app ] && return 0

    log "Installing Ghostty"
    brew install --cask ghostty
}

# The nvim image viewer needs ImageMagick for every format except PNG, and
# librsvg's rsvg-convert to draw SVGs. Both are optional on Linux.
install_image_tools() {
    if ! command_exists magick && ! command_exists convert; then
        case "$OS_NAME" in
            Darwin)
                log "Installing ImageMagick"
                brew install imagemagick
                ;;
            Linux)
                install_optional_package ImageMagick "nvim will only open PNG images" \
                    imagemagick ImageMagick
                ;;
        esac
    fi

    if ! command_exists rsvg-convert; then
        case "$OS_NAME" in
            Darwin)
                log "Installing librsvg"
                brew install librsvg
                ;;
            Linux)
                install_optional_package librsvg "nvim will draw SVGs with ImageMagick, less faithfully" \
                    librsvg2-bin librsvg2-tools
                ;;
        esac
    fi
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

resolve_dotfiles_dir() {
    local dir

    if dir="$(local_checkout_dir)"; then
        DOTFILES_DIR="$dir"
        LOCAL_CHECKOUT=1
    fi
}

sync_repo() {
    if [ -n "$LOCAL_CHECKOUT" ]; then
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

    # Ghostty only runs on the Mac; remote machines are used through it.
    if [ "$OS_NAME" = "Darwin" ]; then
        link "$DOTFILES_DIR/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
        link "$DOTFILES_DIR/ghostty/themes" "$HOME/.config/ghostty/themes"
    fi
}

# Everything that has to go before our Neovim config is linked: a config that
# isn't ours, plus plugins, state and cache from any previous setup. Nothing
# once ours is linked: then they are ours too (plugins, undo history, build
# presets), kept on updates.
nvim_leftovers() {
    local path

    if [ -e "$NVIM_CONFIG" ] || [ -L "$NVIM_CONFIG" ]; then
        [ "$(readlink "$NVIM_CONFIG")" != "$DOTFILES_DIR/nvim" ] || return 0
        printf '%s\n' "$NVIM_CONFIG"
    fi

    for path in "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"; do
        if [ -e "$path" ] || [ -L "$path" ]; then
            printf '%s\n' "$path"
        fi
    done
}

# Asked up front so the prompt doesn't wait halfway through a long install.
# Without a terminal to ask on, nothing is deleted.
ask_nvim_reset() {
    local answer=""

    NVIM_LEFTOVERS="$(nvim_leftovers)"
    if [ -z "$NVIM_LEFTOVERS" ]; then
        NVIM_RESET=yes
        return
    fi

    NVIM_RESET=no
    if ! (: </dev/tty) 2>/dev/null; then
        warn "no terminal to confirm the Neovim reset; Neovim config is left untouched"
        return
    fi

    {
        printf 'Neovim will be reset to the dotfiles config. This deletes:\n'
        printf '%s\n' "$NVIM_LEFTOVERS" | sed 's/^/  /'
        printf 'Continue? [y/N] '
    } >/dev/tty
    read -r answer </dev/tty || true

    case "$answer" in
        y | Y | yes | Yes | YES) NVIM_RESET=yes ;;
        *) warn "Neovim config is left untouched" ;;
    esac
}

reset_nvim_config() {
    local path

    [ "$NVIM_RESET" = yes ] || return 0

    if [ -n "$NVIM_LEFTOVERS" ]; then
        while IFS= read -r path; do
            rm -rf "$path"
            log "Removed $path"
        done <<<"$NVIM_LEFTOVERS"
    fi

    link "$DOTFILES_DIR/nvim" "$NVIM_CONFIG"
}

# Install the plugins and build the syntax parsers now, so the first start of
# nvim is instant. On updates, plugins installed before are moved to the
# versions in nvim-pack-lock.json (nvim itself only installs missing ones).
# Not fatal: nvim also installs plugins and parsers on its own start.
bootstrap_nvim() {
    [ "$NVIM_RESET" = yes ] || return 0

    log "Installing Neovim plugins and syntax parsers"
    PATH="$HOME/.local/bin:$PATH" nvim --headless \
        "+lua vim.pack.update(nil, { target = 'lockfile', force = true })" \
        "+lua require('config.treesitter').install():wait(600000)" +qa </dev/null >/dev/null 2>&1 \
        || warn "Neovim setup did not finish; it will continue on the first start"
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
    resolve_dotfiles_dir
    ask_nvim_reset
    install_dependencies
    sync_repo
    install_starship
    install_neovim
    install_editor_tools
    install_cpp_tools
    install_python_tools
    install_nerd_font
    install_ghostty
    install_image_tools
    link_configs
    reset_nvim_config
    bootstrap_nvim
    install_zsh_loader
    set_login_shell

    log "Done. Restart the terminal or run: exec zsh"
}

main "$@"
