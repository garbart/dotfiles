# Dotfiles

zsh + Starship + Neovim + Ghostty setup for macOS and Linux (Ubuntu, CentOS,
Rocky Linux). Neovim is set up as a VSCode-like editor with JetBrains colors
that switch between light and dark together with macOS.

![Terminal prompt screenshot](./screenshot.png)

## Install

```bashÎÎÎ∂
curl -fsSL https://raw.githubusercontent.com/garbart/dotfiles/main/install.sh | bash
```

Run as a regular user (not `| sudo bash`: everything would go to root's
home). The script asks for `sudo` only for what it can't do without: missing
`git`, `zsh`, `curl`, `tar`, `gzip` or `gcc`, and switching the login shell
to zsh. Optional packages on Linux (clangd, ImageMagick, librsvg) are
installed only when sudo needs no password; otherwise a warning names them,
to install some other way.
Run the same command again to update.

What it does:

- installs Homebrew on macOS, or `git`, `zsh`, `curl`, `gcc` on Linux if
  missing;
- installs Starship (Homebrew on macOS, `~/.local/bin` on Linux);
- installs Neovim (Homebrew on macOS, official release in `~/.local/opt/nvim`
  on Linux, which needs glibc 2.35+);
- installs ripgrep and the tree-sitter CLI for search and syntax highlighting
  (Homebrew on macOS, prebuilt binaries in `~/.local/bin` on Linux);
- installs CMake and Conan for C++ builds (Homebrew on macOS; on Linux their
  official builds in `~/.local/opt`, when missing or CMake is older than
  3.28) and clangd for code navigation, completion and errors (it comes with
  the Command Line Tools on macOS, from the distro on Linux);
- installs basedpyright for Python's code navigation, completion and errors,
  with uv (Homebrew on macOS, a prebuilt binary in `~/.local/bin` on Linux),
  which brings the Python and Node it needs (a failed install only warns);
- installs JetBrains Mono Nerd Font on macOS. Ghostty has the icons built in;
  in other terminals select "JetBrainsMono Nerd Font Mono" once, otherwise
  icons show up as `?`;
- installs Ghostty on macOS, the terminal to run nvim in: it can draw images;
- installs ImageMagick, which nvim needs to open images other than PNG, and
  librsvg to draw SVGs (optional on Linux: a failed install only warns);
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
`:q` quits nvim from the editor or the tree (in a split editor it closes the
split); in the Russian layout it's typed by the same keys, `Жй`. A shell goes in a Ghostty split next to nvim: `Cmd+D`
(right) or `Cmd+Shift+D` (below).

Typing works right away, as in VSCode: an open file is always ready for
input, after opening it, clicking into it (the cursor goes where you click)
or coming back from the tree or a picker. Text selected with the mouse,
Shift+click (from the cursor to the click) or Cmd+A is replaced by what you
type, Cmd+C keeps it selected, and Cmd+Z undoes what was typed since the
last pause. Esc gives Vim's normal mode (for `:q` and the like); a click
brings typing back.

Laid out like VSCode: the tree has a header with the project name (`[SSH:
host]` when remote) and buttons for new file, new folder and collapse all
(the tree updates by itself), in the row of the tabs. There is no status
bar: the editor goes down to the bottom of the screen. A folder opens and
closes with a click on its chevron or a double click on its name. Files git
ignores (like build folders) are shown like any other; right click > Hide
hides them. With no tabs open the editor shows a start screen with the
project, its branch and the main shortcuts (and a classic cheat code from
the 80s). The terminal tab is named after the project.

In the tree Cmd+C copies the path of the file or folder under the cursor,
from the project's folder, and Cmd+Shift+C its full path. Cmd+V pastes
files copied in Finder (or paths copied with Cmd+C) into the folder under
the cursor, or the folder of the file under it; a name already there gets
" copy", " copy 2"... A file or folder dragged with the mouse moves to the
folder it is dropped on: while dragging, its name follows the mouse with
where it would go, and that folder is highlighted. Tabs of moved files
follow them. Cmd+Backspace moves the file or folder under the cursor to the
Trash and closes its tabs, as Cmd+W does: the tab next to it shows, or the
start screen after the last one (so do `d` and the Delete item of the
right-click menu).
Cmd+Z / Cmd+Shift+Z in the tree undo and redo pastes, moves and deletes.
Several files and folders can be selected: Ctrl+click adds or takes away
one (Ghostty doesn't pass Cmd with clicks), Shift+click selects from the one
clicked last; a click or Esc clears the selection. Deleting, dragging and
copying paths then act on all of them.

Right click > Hide hides the files and folders selected (or the one clicked)
from the tree. The list is kept in the project, in `.nvim/settings.json`, in
the format of VSCode's `files.exclude` (glob patterns like `"**/*.o": true`
can be added by hand). While something is hidden the header has an eye
button: it shows the hidden files, dimmed, and hides them again; Unhide in
the right-click menu of the shown ones brings them back.

Scrolling never goes into empty space: down stops when the end of the file
reaches the bottom of the window, sideways at the end of the longest line on
screen. The tree doesn't scroll sideways at all; names too long for it are
cut with `…`.

Files save themselves, like VSCode with auto save on: right after a change,
a second after you stop typing, and when you switch files, close a tab or
leave nvim. Saving and undo show no messages.

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
| `Cmd+S`                      | format C / C++ and save (also autosaved)    |
| `Cmd+W` / `Space w`          | close the tab (the one next to it shows)    |
| `Cmd+Shift+T`                | reopen the last closed tab                  |
| `Ctrl+Tab` / `Ctrl+Shift+Tab` | next / previous tab                        |
| `Cmd+B` / `Space e`          | show / hide the file tree                   |
| `Cmd+/`                      | comment / uncomment                         |
| `[b` / `]b`, click           | previous / next tab                         |
| click the chevron, `za`      | fold / unfold a block                       |
| `Cmd+Shift+V` / `Space m`    | Markdown: source / preview; CSV: table / text |

Editing works as in any Mac app:

| Key                          | Action                                         |
| ---------------------------- | ---------------------------------------------- |
| `Cmd+A`                      | select all                                     |
| `Cmd+C` / `Cmd+X`            | copy / cut the selection, or the whole line    |
| `Cmd+V`                      | paste at the cursor (a copied line goes above) |
| `Cmd+Z` / `Cmd+Shift+Z`      | undo / redo                                    |
| `Tab` / `Shift+Tab`          | indent the selection / outdent it or the line  |
| `Cmd+G`                      | revert git changes in the selection or line    |
| `Cmd+←` / `Cmd+→`            | line start / end                               |
| `Option+←` / `Option+→`      | word left / right                              |
| `Cmd+Backspace`              | delete to line start                           |
| `Option+Backspace`           | delete the word before the cursor              |
| `Option+Fn+Backspace`        | delete the word after the cursor               |

They work in insert mode too and in any keyboard layout, as do the single
keys of the tree, the start screen and Vim's normal mode (`d`, `r`, `j`...
are the same keys in the Russian layout). In the zsh prompt
Cmd+W closes the shell (and so the Ghostty tab), Cmd+C copies the terminal
selection, Cmd+K clears the screen; the other forwarded shortcuts do nothing
there. Ghostty's own tabs switch with Cmd+1…9 and Cmd+Shift+[ / ] (Ctrl+Tab
is nvim's), and Cmd+Shift+W closes one. Cmd+←/→ in nvim replace Vim's
Ctrl+A (increment) and Ctrl+E (scroll a line), since Ghostty sends them as
those keys.

Right click opens a short menu for what is under the mouse. Each item shows
a key on the right, as in Claude's menus: press it while the menu is open
(it's the letter of the item's Cmd shortcut where there is one, X for Cut,
and works in the Russian layout too); the mouse, the arrows and Enter work
as usual, Esc closes the menu.

In code the menu has go to definition, find all references and rename (with
a language server, see below); cut / copy / paste; revert the git changes of
the line or selection (when it has any) and copy a link to it on the git
host; select all, comment and the command palette. The link goes to the host
of the `origin` remote: GitHub, GitLab, Bitbucket, Gitea / Forgejo, Azure
DevOps (any other host gets GitLab's links), to the commit when it is
pushed. In the tree: new file, new folder, rename, delete, copy path and
hide; in a terminal: copy / paste.

Images open inside nvim in Ghostty (any terminal with the kitty graphics
protocol, also over SSH), SVGs too. Terminal.app can't show them. SVGs made for both
themes, like draw.io's, follow light and dark as on GitHub, labels on arrows
on the editor's background.

An image opens fit to the window's width. A click zooms in around the
clicked spot, 1.5x then 3x, and the next click fits it again. Each zoom is
as sharp as the screen allows: SVGs are drawn anew, photos come from the
full-size file. The wheel or the
trackpad scrolls a zoomed image up, down and sideways (Shift+wheel:
sideways, Ctrl+wheel: a window at a time).

Markdown opens as source; an image linked there pops up while the cursor is
on its link. Cmd+Shift+V switches to the preview, which looks like GitHub's
and is read-only: no cursor and no typing, but text can be selected and
copied. Tables have a line between rows. Images are drawn in place, as wide
as the window; a click on one opens it (with zoom). Ctrl+click on a link follows it, in both views: to a
heading (`#anchor`), another file (a Markdown one opens in the same view),
an image, or a web address (in the browser); Ctrl+- goes back.

CSV and TSV files open as a table: columns aligned and colored, the header
row kept at the top while scrolling. Only the display changes, the file stays
as it is, and typing works in the table. The delimiter (comma, semicolon, tab
or bar) is detected from the file.

Files over 50 MB aren't read when opened: their tab shows the size and a
Load button (click it or press Enter). A file loaded once opens right away
until nvim quits.

Plugins are managed by the built-in `vim.pack` (Neovim 0.12+) and pinned in
`nvim/nvim-pack-lock.json`. The config lives in `nvim/lua/config/`, one file
per area.

## C++

C and C++ files get clangd, the language server VSCode's clangd extension
runs too, and Python files basedpyright (Pyright, which VSCode's Pylance is
built on; it uses the project's `.venv` or `venv`, else the Python nvim was
started with):

- **Colors by meaning** (types, macros, members, parameters), as in CLion,
  over the syntax colors.
- **Completion** while typing, with the documentation of the selected
  suggestion and the parameters of the function being called. `Enter` or
  `Tab` accepts, `Esc` closes the list, `Ctrl+Space` opens it; a completed
  function's arguments are placeholders, `Tab` goes to the next one.
- **Errors and warnings** underlined as they come; the message of the
  cursor's line shows at its end.
- **Navigation**: go to definition (`F12` or `Ctrl+click`), all references
  in a list like Find in Files (`Shift+F12`), symbols of the file
  (`Cmd+Shift+O`), back / forward (`Ctrl+-` / `Ctrl+Shift+-`).
- **Rename** (`F2`) in every file that uses the name; files that weren't
  open are saved and don't open as tabs.
- **Formatting** (C and C++): `Cmd+S` formats by the project's
  `.clang-format` before saving; saving by itself doesn't format.

Building, running and debugging happen in the shell (a Ghostty split,
`Cmd+D`). clangd reads the compile commands CMake writes when configuring
(`CMAKE_EXPORT_COMPILE_COMMANDS`), from the build configured last: nvim gives
it the newest `compile_commands.json` in the project, wherever the build went
(`build/`, `cmake-build-debug/`, `.build/release/`, `out/build/x64/`; git
submodules' own builds don't count). No `.clangd` is needed for that, and a
`CompilationDatabase` in one is overridden. When another build gets
configured (in the split), clangd restarts with it as soon as nvim gets the
focus back. It asks the compiler from the compile commands for its standard
library headers, so Homebrew's GCC (`g++-15`) and toolsets in `/opt` work
too.

## Git in zsh

Short commands for git (`ghelp` lists them all):

| Command        | Does                                                       |
| -------------- | ---------------------------------------------------------- |
| `gst`          | status, short                                              |
| `ga` / `gaa`   | add files / everything                                     |
| `gcm "msg"`    | commit with a message                                      |
| `gca`          | add the staged changes to the last commit                  |
| `gpu` / `gpl`  | push (a new branch gets its upstream) / pull               |
| `gpuf`         | force push, unless someone pushed meanwhile                |
| `gd` / `gds`   | diff of unstaged / staged changes                          |
| `gl` / `gla`   | last 20 commits / every branch as a graph                  |
| `gsw` / `gcb`  | switch branch / create one and switch to it                |
| `gb`           | branches, the recent first                                 |
| `gf`           | fetch every remote, drop deleted branches                  |
| `grs` / `gunstage` | discard changes in files / unstage them               |
| `gsta` / `gstp` | stash / pop                                               |
| `grb`, `grbi`, `grbc`, `grba` | rebase, interactive, continue, abort        |
| `gcp`, `gcl`   | cherry-pick, clone                                         |
| `gundo`        | undo the last commit, keeping its changes staged           |
| `gwip` / `gunwip` | commit everything as "wip" / undo that commit           |
| `gsync`        | fetch and rebase this branch on the main one               |
| `gtidy`        | delete local branches already merged into the main one     |
| `groot`        | go to the root of the repository                           |
| `gtoday`       | my commits since midnight, for the standup                 |
| `gweb`         | open this branch on GitHub / GitLab / ... in the browser   |
| `gyolo`        | commit everything with a classic message (no push)         |

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
