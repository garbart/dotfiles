# Git shortcuts. `ghelp` lists them, from the comments after each one here.
# Tab completes their arguments as for git (branches for gsw, files for ga).

_DOTFILES_GIT_ZSH="${${(%):-%x}:A}"

# Every day
alias gst='git status -sb'                        # status, short
alias ga='git add'                                # add files
alias gaa='git add --all'                         # add everything
alias gcm='git commit -m'                         # commit with a message: gcm "fix the thing"
alias gca='git commit --amend --no-edit'          # add the staged changes to the last commit
alias gd='git diff'                               # changes not staged yet
alias gds='git diff --staged'                     # changes staged for the commit
alias gl='git log --oneline --graph --decorate -20'   # the last 20 commits
alias gla='git log --oneline --graph --decorate --all' # every branch, as a graph
alias gpl='git pull'                              # pull
alias gpuf='git push --force-with-lease'          # force push, unless someone pushed meanwhile
alias gf='git fetch --all --prune'                # fetch every remote, drop deleted branches
alias gsw='git switch'                            # switch to a branch
alias gcb='git switch -c'                         # create a branch and switch to it
alias gb='git branch --sort=-committerdate'       # branches, the recent first
alias grs='git restore'                           # discard the changes in files
alias gunstage='git restore --staged'             # unstage files, keeping the changes
alias gsta='git stash push'                       # stash the changes
alias gstp='git stash pop'                        # bring the stashed changes back
alias grb='git rebase'                            # rebase
alias grbi='git rebase -i'                        # rebase interactively
alias grbc='git rebase --continue'                # go on with a rebase
alias grba='git rebase --abort'                   # give up a rebase
alias gcp='git cherry-pick'                       # cherry-pick a commit
alias gcl='git clone'                             # clone

gpu() { # push; a new branch gets its upstream (origin) on the first push
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git push "$@"
    else
        git push -u origin HEAD "$@"
    fi
}
compdef _git gpu=git-push

# Handy
gundo() { # undo the last commit, its changes staged again
    git reset --soft HEAD~1 && git status -sb
}

gwip() { # commit everything as "wip", to come back to later
    git add --all && git commit --no-verify -m wip
}

gunwip() { # undo the last commit if it is a "wip" one
    if [[ "$(git log -1 --format=%s)" == wip ]]; then
        git reset HEAD~1
    else
        echo "The last commit is not a wip one"
    fi
}

groot() { # go to the root of the repository
    cd "$(git rev-parse --show-toplevel)" || return
}

# The remote's main branch: origin/main, origin/master...
_dotfiles_main_branch() {
    git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null ||
        { git rev-parse --verify --quiet origin/main >/dev/null && echo origin/main; } ||
        echo origin/master
}

gsync() { # bring the main branch in: fetch, then rebase this branch on it
    git fetch origin && git rebase "$(_dotfiles_main_branch)"
}

gtidy() { # delete local branches already merged into the main branch
    local main="$(_dotfiles_main_branch)" branch
    git fetch --prune origin
    for branch in $(git branch --merged "$main" --format='%(refname:short)'); do
        [[ "$branch" == "${main#origin/}" || "$branch" == "$(git branch --show-current)" ]] && continue
        git branch -d "$branch"
    done
}

gtoday() { # my commits since midnight, for the standup
    git log --all --since=midnight --author="$(git config user.email)" --format='%C(yellow)%h%Creset %s %C(dim)(%ar, %D)%Creset'
}

gweb() { # open this branch on GitHub / GitLab / ... (over ssh: print the link)
    local url="$(git remote get-url origin 2>/dev/null)" branch="$(git branch --show-current)"
    [[ -n "$url" ]] || { echo "No origin remote"; return 1; }
    url="${url%.git}"
    if [[ "$url" == http*://* ]]; then
        url="https://${${url#*://}#*@}"
    elif [[ "$url" == *://* ]]; then
        # ssh://git@host:2222/path: the web page has no ssh port.
        url="https://${${${url#*://}#*@}/:<->\///}"
    else
        url="https://${${url#*@}/://}"
    fi
    if [[ "$url" == *github* ]]; then
        url="$url/tree/$branch"
    else
        url="$url/-/tree/$branch"
    fi
    echo "$url"
    if [[ -z "$SSH_CONNECTION" ]]; then
        if command -v open >/dev/null 2>&1; then
            open "$url"
        elif command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$url" >/dev/null 2>&1
        fi
    fi
}

gyolo() { # commit everything with a classic message (doesn't push, it's not that yolo)
    local messages=(
        'it works on my machine'
        'fixed it (probably)'
        'trust me'
        '¯\_(ツ)_/¯'
        'final final v2'
        'I have no idea what I am doing'
        'please work'
        'magic, do not touch'
        'temporary (forever)'
        'removed bugs, added new ones'
        'friday deploy'
        'this is fine'
    )
    git add --all && git commit -m "${messages[RANDOM % ${#messages} + 1]}"
}

ghelp() { # this list
    local line name text
    while IFS= read -r line; do
        if [[ "$line" =~ "^alias ([a-z]+)='[^']*' +# (.*)$" ]]; then
            name="$match[1]" text="$match[2]"
        elif [[ "$line" =~ "^([a-z]+)\(\) \{ # (.*)$" ]]; then
            name="$match[1]" text="$match[2]"
        elif [[ "$line" =~ "^# ([A-Za-z ]+)$" ]]; then
            printf '\n\e[1m%s\e[0m\n' "$match[1]"
            continue
        else
            continue
        fi
        printf '  \e[33m%-9s\e[0m %s\n' "$name" "$text"
    done <"$_DOTFILES_GIT_ZSH"
}
