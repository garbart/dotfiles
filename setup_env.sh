#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── GUI detection ────────────────────────────────────
has_gui() {
    [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]
}

# ─── Ghostty (only with GUI) ──────────────────────────
if has_gui; then
    sudo snap install ghostty --classic
    mkdir -p ~/.config/ghostty/themes
    cp "$DOTFILES_DIR/ghostty/config.ghostty" ~/.config/ghostty/config
    cp "$DOTFILES_DIR/ghostty/themes/"* ~/.config/ghostty/themes/
else
    echo "No GUI detected — skipping Ghostty"
fi

# ─── Zsh ─────────────────────────────────────────────
sudo apt install -y zsh
chsh -s "$(which zsh)" "$USER"

# ─── Starship ─────────────────────────────────────────
curl -sS https://starship.rs/install.sh | sh
mkdir -p ~/.config
cp "$DOTFILES_DIR/starship/config" ~/.config/starship.toml
grep -qxF 'eval "$(starship init zsh)"' ~/.zshrc \
    || echo 'eval "$(starship init zsh)"' >> ~/.zshrc

# ─── eza ──────────────────────────────────────────────
sudo apt install -y eza

# ─── Zsh aliases & keybinds ───────────────────────────
cat >> ~/.zshrc << 'EOF'

# aliases
alias lh='eza -al --group-directories-first'
alias ll='eza -l --group-directories-first'
alias ls='eza -lF --color=always --sort=size | grep -v /'

# word navigation with Ctrl+Left/Right
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
EOF

# ─── Vim clipboard ────────────────────────────────────
sudo apt install -y xclip
mkdir -p ~/.vim
cp "$DOTFILES_DIR/vim/vimrc" ~/.vim/vimrc
grep -qxF 'source ~/.vim/vimrc' ~/.vimrc 2>/dev/null \
    || echo 'source ~/.vim/vimrc' >> ~/.vimrc
