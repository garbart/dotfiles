# Dotfiles

Tiny zsh + Starship setup for macOS and Linux (Ubuntu, CentOS, Rocky Linux).

![Terminal prompt screenshot](./screenshot.png)

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | bash
```

Run as a regular user: the script asks for `sudo` only when it needs it.
Run the same command again to update.

What it does:

- installs Homebrew on macOS, or `git`, `zsh`, `curl` on Linux if missing;
- installs Starship (Homebrew on macOS, `~/.local/bin` on Linux);
- clones this repo into `~/.local/share/dotfiles`;
- symlinks `~/.config/starship.toml` and `~/.config/zsh/zshrc` to the clone;
- appends one `source` line to `~/.zshrc` and makes zsh the login shell.

Existing configs are moved to `~/.local/state/dotfiles/backups/` instead of
being overwritten. No temp files are left behind.

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
