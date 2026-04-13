#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Real user detection (handle `sudo ./setup_env.sh`) ──
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    REAL_USER="$USER"
    REAL_HOME="$HOME"
fi

# Run with root privileges (works both with and without sudo)
as_root() {
    if [ "$(id -u)" = "0" ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# Run as the real (non-root) user
as_user() {
    if [ "$(id -u)" = "0" ]; then
        sudo -u "$REAL_USER" "$@"
    else
        "$@"
    fi
}

# ─── GUI detection ────────────────────────────────────
has_gui() {
    [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]
}

# ─── Ghostty (only with GUI) ──────────────────────────
if has_gui; then
    as_root snap install ghostty --classic
    as_user mkdir -p "$REAL_HOME/.config/ghostty/themes"
    ln -sf "$DOTFILES_DIR/ghostty/config.ghostty" "$REAL_HOME/.config/ghostty/config"
    for f in "$DOTFILES_DIR/ghostty/themes/"*; do
        ln -sf "$f" "$REAL_HOME/.config/ghostty/themes/$(basename "$f")"
    done
else
    echo "No GUI detected — skipping Ghostty"
fi

# ─── Zsh ─────────────────────────────────────────────
as_root apt install -y zsh
chsh -s "$(which zsh)" "$REAL_USER"

# ─── Starship ─────────────────────────────────────────
STARSHIP_TMP=$(mktemp)
curl -sS https://starship.rs/install.sh -o "$STARSHIP_TMP"
as_root sh "$STARSHIP_TMP" --yes
rm "$STARSHIP_TMP"
as_user mkdir -p "$REAL_HOME/.config"
ln -sf "$DOTFILES_DIR/starship/config" "$REAL_HOME/.config/starship.toml"
grep -qxF 'eval "$(starship init zsh)"' "$REAL_HOME/.zshrc" \
    || echo 'eval "$(starship init zsh)"' >> "$REAL_HOME/.zshrc"

# ─── eza ──────────────────────────────────────────────
as_root apt install -y eza

# ─── Zsh aliases & keybinds ───────────────────────────
cat >> "$REAL_HOME/.zshrc" << 'EOF'

# aliases
alias lh='eza -al --group-directories-first'
alias ll='eza -l --group-directories-first'
alias ls='eza -lF --color=always --sort=size | grep -v /'

# word navigation with Ctrl+Left/Right
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
EOF

# ─── Vim clipboard ────────────────────────────────────
as_root apt install -y xclip
as_user mkdir -p "$REAL_HOME/.vim"
cp "$DOTFILES_DIR/vim/vimrc" "$REAL_HOME/.vim/vimrc"
grep -qxF 'source ~/.vim/vimrc' "$REAL_HOME/.vimrc" 2>/dev/null \
    || echo 'source ~/.vim/vimrc' >> "$REAL_HOME/.vimrc"


# ─── Neovim ───────────────────────────────────────────

as_root apt update
as_root apt install -y \
  git \
  curl \
  build-essential \
  cmake \
  clangd \
  lldb \
  gdb \
  python3-pip \
  ripgrep \
  fd-find \
  sqlite3 \
  libpq-dev \
  postgresql-client

curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
tar xzf nvim-linux-x86_64.tar.gz
as_root mv nvim-linux-x86_64 /opt/nvim
as_root ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim
rm nvim-linux-x86_64.tar.gz

LAZY_PATH="$REAL_HOME/.local/share/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_PATH" ]; then
  as_user git clone https://github.com/folke/lazy.nvim.git "$LAZY_PATH"
fi

as_user mkdir -p "$REAL_HOME/.config/nvim"
ln -sf "$DOTFILES_DIR/nvim/init.lua" "$REAL_HOME/.config/nvim/init.lua"

echo "Done"
