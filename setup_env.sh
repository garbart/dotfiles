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


# ─── Neovim ───────────────────────────────────────────

sudo apt update
sudo apt install -y \
  neovim \
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

LAZY_PATH="$HOME/.local/share/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_PATH" ]; then
  git clone https://github.com/folke/lazy.nvim.git "$LAZY_PATH"
fi

mkdir -p ~/.config/nvim

cat > ~/.config/nvim/init.lua << 'EOF'
-- ========================
-- Bootstrap lazy.nvim
-- ========================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({

  -- LSP
  { "neovim/nvim-lspconfig" },

  -- Mason
  { "williamboman/mason.nvim", config = true },
  { "williamboman/mason-lspconfig.nvim" },

  -- Completion
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "L3MON4D3/LuaSnip" },

  -- Treesitter
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },

  -- Telescope
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  -- Git
  { "lewis6991/gitsigns.nvim", config = true },

  -- DAP
  { "mfussenegger/nvim-dap" },
  { "rcarriga/nvim-dap-ui", dependencies = { "mfussenegger/nvim-dap" } },

  -- DB
  { "tpope/vim-dadbod" },
  { "kristijanhusak/vim-dadbod-ui" },
  { "kristijanhusak/vim-dadbod-completion" },

})

-- ========================
-- LSP (clangd)
-- ========================
local lspconfig = require("lspconfig")

lspconfig.clangd.setup({
  cmd = {
    "clangd",
    "--background-index",
    "--clang-tidy",
    "--completion-style=detailed",
    "--header-insertion=iwyu",
    "--query-driver=/usr/bin/g++-15"
  },
})

-- ========================
-- CMP
-- ========================
local cmp = require("cmp")
cmp.setup({
  mapping = cmp.mapping.preset.insert({
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
  }),
  sources = {
    { name = "nvim_lsp" },
  },
})

-- ========================
-- Treesitter
-- ========================
require("nvim-treesitter.configs").setup({
  ensure_installed = { "cpp", "c", "lua" },
  highlight = { enable = true },
})

-- ========================
-- Telescope
-- ========================
require("telescope").setup()

-- ========================
-- DAP (LLDB)
-- ========================
local dap = require("dap")

dap.adapters.lldb = {
  type = "executable",
  command = "lldb-dap", -- fallback: lldb-vscode
  name = "lldb"
}

dap.configurations.cpp = {
  {
    name = "Launch",
    type = "lldb",
    request = "launch",
    program = function()
      return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
    end,
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
  },
}

-- DAP UI
local dapui = require("dapui")
dapui.setup()

vim.keymap.set("n", "<F5>", dap.continue)
vim.keymap.set("n", "<F10>", dap.step_over)
vim.keymap.set("n", "<F11>", dap.step_into)
vim.keymap.set("n", "<F12>", dap.step_out)
vim.keymap.set("n", "<Leader>b", dap.toggle_breakpoint)

dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end

-- ========================
-- DB UI
-- ========================
vim.g.db_ui_use_nerd_fonts = 1

-- ========================
-- General
-- ========================
vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true

EOF

echo "Done"
