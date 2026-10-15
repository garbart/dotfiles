# Dotfiles

zsh + Starship + Neovim + Ghostty setup for macOS and Linux (Ubuntu, CentOS,
Rocky Linux). Neovim is set up as a VSCode-like editor with JetBrains colors
that switch between light and dark together with macOS.

![Terminal prompt screenshot](./screenshot.png)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | bash
```

Run as a regular user: the script asks for `sudo` only when it needs it.
Run the same command again to update.

What it does:

- installs Homebrew on macOS, or `git`, `zsh`, `curl`, `gcc` on Linux if
  missing;
- installs Starship (Homebrew on macOS, `~/.local/bin` on Linux);
- installs Neovim (Homebrew on macOS, official release in `~/.local/opt/nvim`
  on Linux, which needs glibc 2.35+);
- installs ripgrep and the tree-sitter CLI for search and syntax highlighting
  (Homebrew on macOS, prebuilt binaries in `~/.local/bin` on Linux);
- installs JetBrains Mono Nerd Font on macOS. Ghostty has the icons built in;
  in other terminals select "JetBrainsMono Nerd Font Mono" once, otherwise
  icons show up as `?`;
- installs Ghostty on macOS, the terminal to run nvim in: it can draw images;
- installs ImageMagick, which nvim needs to open images other than PNG
  (optional on Linux: a failed install only warns);
- clones this repo into `~/.local/share/dotfiles`;
- symlinks `~/.config/starship.toml`, `~/.config/zsh/zshrc`,
  `~/.config/nvim` and, on macOS, `~/.config/ghostty/` to the clone;
- installs the Neovim plugins and syntax parsers;
- appends one `source` line to `~/.zshrc` and makes zsh the login shell.

Nothing Ghostty-related is installed on Linux: remote machines are used
through Ghostty over ssh, which brings its terminfo along.

Existing zsh, Starship and Ghostty configs are moved to
`~/.local/state/dotfiles/backups/` instead of being overwritten. No temp files
are left behind.

Neovim is reset instead: the script lists the existing `~/.config/nvim`,
`~/.local/share/nvim`, `~/.local/state/nvim` and `~/.cache/nvim`, asks for
confirmation and deletes them. Answer no (or run without a terminal) and
Neovim config is left untouched.

## Neovim

Run `nvim` (or `nvim <dir>`) to open a directory as a project: file tree on
the left, tabs and editor on the right. `nvim <file>` opens just the file.

Laid out like VSCode: the tree has a header with the project name (`[SSH:
host]` when remote) and buttons for new file, new folder and collapse all
(the tree updates by itself). With no tabs open the editor shows a start
screen with the project, its branch and the main shortcuts. The terminal tab
is named after the project.

Ghostty and Neovim share the JetBrains palettes (from
[jb.nvim](https://github.com/nickkadutskyi/jb.nvim)) and follow the macOS
light/dark setting, also in nvim running over ssh. The prompt uses the
terminal's ANSI colors, so it follows too.

Shortcuts work like in VSCode. Cmd shortcuts need Ghostty (it forwards them to
nvim, also over ssh); the Space ones work in any terminal.

| Key                          | Action                                      |
| ---------------------------- | ------------------------------------------- |
| `Cmd+P` / `Space Space`      | quick open                                  |
| `Cmd+Shift+F` / `Space /`    | find in files                               |
| `Cmd+Shift+P` / `Space p`    | command palette                             |
| `Cmd+F`                      | find in file                                |
| `Cmd+S`                      | save                                        |
| `Cmd+W` / `Space w`          | close the tab (asks to save changes)        |
| `Cmd+1`…`Cmd+8`, `Cmd+9`     | go to tab 1…8, to the last tab              |
| `Cmd+B` / `Space e`          | show / hide the file tree                   |
| `Cmd+/`                      | comment / uncomment                         |
| `` Ctrl+` `` / `Space t`     | terminal panel                              |
| `[b` / `]b`, click           | previous / next tab                         |
| click the chevron, `za`      | fold / unfold a block                       |
| `Cmd+Shift+V` / `Space m`    | Markdown: switch between source and preview |

Editing works as in any Mac app:

| Key                          | Action                                         |
| ---------------------------- | ---------------------------------------------- |
| `Cmd+A`                      | select all                                     |
| `Cmd+C` / `Cmd+X`            | copy / cut the selection, or the whole line    |
| `Cmd+V`                      | paste at the cursor (a copied line goes above) |
| `Cmd+Z` / `Cmd+Shift+Z`      | undo / redo                                    |
| `Cmd+←` / `Cmd+→`            | line start / end                               |
| `Option+←` / `Option+→`      | word left / right                              |
| `Cmd+Backspace`, `Option+Backspace` | delete to line start, delete word       |

They work in insert mode too and in any keyboard layout. In the zsh prompt
Cmd+W closes the shell (and so the Ghostty tab), Cmd+C copies the terminal
selection; the other forwarded shortcuts do nothing there. Ghostty's own tabs
switch with Cmd+Shift+[ and Cmd+Shift+]. Cmd+←/→ in nvim replace Vim's
Ctrl+A (increment) and Ctrl+E (scroll a line), since Ghostty sends them as
those keys.

Right click opens a short menu for what is under the mouse: cut / copy /
paste, select all, comment and the command palette in code; new file, new
folder, rename, delete and copy path in the tree; close / close others /
close all on a tab; paste in the terminal.

Images open inside nvim in Ghostty (any terminal with the kitty graphics
protocol, also over SSH). Terminal.app can't show them.

Plugins are managed by the built-in `vim.pack` (Neovim 0.12+) and pinned in
`nvim/nvim-pack-lock.json`. The config lives in `nvim/lua/config/`, one file
per area.

## Options

Options are passed as environment variables:

```bash
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | DOTFILES_BRANCH=ft-nvim bash
```

| Variable          | Default                                  |
| ----------------- | ---------------------------------------- |
| `DOTFILES_BRANCH` | `main`                                   |
| `DOTFILES_REPO`   | `https://github.com/garbart/dotfiles.git` |
| `DOTFILES_DIR`    | `~/.local/share/dotfiles`                |

To work on the dotfiles themselves, run `./install.sh` from a checkout: it
links that checkout instead of cloning.
