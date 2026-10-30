# RepoSweep

<img src="Resources/AppIcon.png" width="128" alt="">

A small macOS app for keeping a folder full of git checkouts tidy. Pick a
working directory, and RepoSweep lists every repository under it, with a link
to each one on GitHub and its open pull requests underneath.

- **Update** — `git fetch --prune`, then a fast-forward-only `git pull` of the
  checked-out branch, then reload the pull request list.
- **Cleanup** — delete local branches whose work has actually landed, and
  the worktrees left behind with them.
- **Update all** (⌘R) first rescans the working directory, so repositories
  added or deleted since the last look join or leave the list, then updates
  every one, a few at a time. **Cleanup all** (⇧⌘K) cleans up every one.

The status bar at the bottom shows how much space the working directory takes
up on disk and how much is free on its volume, and each repository shows its
own size. All of it is measured again after every scan, update and cleanup.
Cleanup logs the space it freed: the size of each worktree it removed.

Pin a repository (the pin button, or right-click) to keep it at the top of
the list. Pins are saved, and shared by every tab that lists the repository.

## What Cleanup deletes

A branch marked `[gone]` (its remote branch was deleted) is only a candidate:
that alone doesn't mean it was merged. For each candidate RepoSweep asks
GitHub (`gh pr list --head <branch>`):

| PR for the branch | Result |
| --- | --- |
| merged | deleted |
| open (e.g. a stacked PR) | kept |
| none, but its commits or an equal squashed patch are in the default branch | deleted |
| none, and not in the default branch | kept, reported for manual review |

If the branch to delete is the one checked out, RepoSweep switches the
checkout to the default branch, fast-forwards it to `origin`, then deletes the
branch, but only when there are no local changes.

Worktrees: stale registrations are pruned; a worktree on a deleted branch is
removed along with it; a detached worktree whose commit is already in the
default branch is removed. Nothing is ever removed with `--force`. A locked
worktree, or one with uncommitted work, is kept and named in the log, and so
is its branch.

Tick **Dry run** to see what Cleanup would do without changing anything.

## Tabs

**+** next to the tabs (⌘T) opens a new tab for another working directory.
⌘W (or the × on hover) closes the current tab, and the window once it's the
last one; ⇧⌘[ and ⇧⌘] switch tabs. Open tabs and the selected one are
restored on the next launch.

## Repository discovery

Every directory under the working directory that contains a `.git` is a
repository; the search doesn't go inside a repository. If the working
directory is itself a repository, paths it ignores are skipped. Linked
worktrees are left out of the list, because cleaning up their main checkout
handles them.

## Requirements

- macOS 14 or later
- `git` and the [GitHub CLI](https://cli.github.com) (`gh auth login`), in
  `/opt/homebrew/bin`, `/usr/local/bin` or `/usr/bin`

## Build

```bash
./scripts/build-app.sh            # builds build/RepoSweep.app
./scripts/build-app.sh --install  # and copies it to /Applications
```

The icon is a Liquid Glass icon, `Resources/AppIcon.icon`, made of SVG
layers; edit it in Icon Composer (bundled with Xcode). `build-app.sh` compiles
it with `actool`, so building needs Xcode rather than just the command line
tools. `Resources/AppIcon.png` is a rendered preview for this README.

The app is ad-hoc signed and not notarized, so it's meant to be built
locally. For development:

```bash
swift run RepoSweep
swift test
```

## Contributing

Pull requests are squash-merged, so a PR's title becomes the commit subject
on `main`, and CI checks it is a conventional commit subject:
`<type>[(scope)][!]: <description>`, with type one of `feat`, `fix`,
`refactor`, `docs`, `test`, `chore`, `perf`, `ci`, `build` or `revert`. CI
also runs `swift test`, builds the app with `build-app.sh` and lints the
scripts with ShellCheck; all of it has to pass before a PR can merge.

## License

MIT
