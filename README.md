# Dotfiles

One command turns a Mac or a Linux server into a comfortable terminal setup:
zsh with Starship, Ghostty, and Neovim that feels like VSCode — a file tree,
tabs, the mouse, Cmd shortcuts, search, code navigation for C++ and Python —
in JetBrains colors that follow the light and dark theme of macOS.

It's for those who spend their day on remote machines over SSH and don't want
to give up a desktop editor there: the same editor and shell on the laptop and
on every server, set up with one line and updated with the same line.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/editor-dark.png">
  <img alt="Neovim on a server over SSH: the file tree, tabs and a Markdown file" src="docs/screenshots/editor-light.png">
</picture>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/shell-dark.png">
  <img alt="The zsh prompt with the git branch" src="docs/screenshots/shell-light.png">
</picture>

The screenshots follow your GitHub theme, as the setup follows macOS: switch
it to see the other one.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | bash
```

Works on macOS and Linux (Ubuntu, CentOS, Rocky Linux). Run it as a regular
user, and again to update. It installs what's missing (Neovim, language
servers, fonts, Ghostty on macOS) and links the configs; `sudo` is asked for
system packages only. Old zsh, Starship and Ghostty configs are kept in
`~/.local/state/dotfiles/backups/`, an existing Neovim config is deleted after
a confirmation.

In zsh, `ghelp` lists the git shortcuts.

## Options

Options are environment variables:

```bash
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | DOTFILES_BRANCH=ft-nvim bash
```

| Variable          | Default                                   |
| ----------------- | ----------------------------------------- |
| `DOTFILES_BRANCH` | `main`                                    |
| `DOTFILES_REPO`   | `https://github.com/garbart/dotfiles.git` |
| `DOTFILES_DIR`    | `~/.local/share/dotfiles`                 |

To work on the dotfiles themselves, run `./install.sh` from a checkout: it
links that checkout instead of cloning.
