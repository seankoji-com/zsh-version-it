# zsh-version-it

Bump an npm package version onto a fresh branch, ready to commit.

`versionit <keyword|version>` calculates the version with npm, creates a branch named after it, updates `package.json` and the existing lockfile, and stages those files. Nothing is committed or pushed. It asks for confirmation before making changes. Version scripts are disabled. The branch prefix is configurable.

The package and any non-ignored lockfile must be tracked and clean. An ignored, untracked lockfile is left untouched, with a warning that it may need a manual update; tracked lockfiles still count even when an ignore pattern matches them. Multiple relevant lockfiles are rejected instead of guessing which to use. npm handles `package-lock.json` and `npm-shrinkwrap.json`, and pnpm handles `pnpm-lock.yaml`; these managers must be installed when their lockfile exists. If one npm lockfile is tracked and the other is ignored, the command stops because npm could modify the ignored file. For a non-workspace package, `yarn.lock` does not record the package's own version, so it needs no install for a version-only change. With no relevant lockfile, none is created. If an ancestor directory has a relevant lockfile, or the package is a Yarn workspace root with a lockfile (even an ignored one), the command stops rather than risk leaving a workspace lockfile stale. If an update fails after branch creation, inspect the working tree before retrying.

## Installation

### Manual

Clone the repo and source the plugin from your `.zshrc`:

```zsh
git clone https://github.com/seankoji-com/zsh-version-it ~/.zsh/zsh-version-it
echo 'source ~/.zsh/zsh-version-it/zsh-version-it.plugin.zsh' >> ~/.zshrc
```

### zinit

```zsh
zinit light seankoji-com/zsh-version-it
```

### oh-my-zsh

Clone into your custom plugins directory:

```zsh
git clone https://github.com/seankoji-com/zsh-version-it \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-version-it
```

Then add it to the `plugins` array in your `.zshrc`:

```zsh
plugins=(... zsh-version-it)
```

Requires `node`, `npm`, and the package manager for the existing lockfile on your `PATH`. Run it from a git repository containing a `package.json`.

## Usage

Print the current version from `./package.json`:

```zsh
version
```

Bump the version onto a new branch. Accepts any npm version keyword or an explicit version:

```zsh
versionit patch      # 1.2.3 -> 1.2.4
versionit minor      # 1.2.3 -> 1.3.0
versionit major      # 1.2.3 -> 2.0.0
versionit 1.12.1     # explicit version
```

`versionit` prints its plan and prompts before making changes. On confirmation it creates a branch (default `patch/<new-version>`), bumps the version, updates the existing lockfile, and stages the version files for you to review and commit.

If an npm or pnpm lockfile refresh fails, inspect `git status` and the package and lockfile diffs, then run `versionit resume` from the same package directory. It shows the retry plan and asks for confirmation. The retry disables lifecycle scripts and stages only the package and lockfile after a successful refresh. Unrelated staged and unstaged changes remain in place.

The command records the branch, commit, package directory, version and target file hashes in `versionit-resume.json` inside the worktree's Git directory. It refuses a missing or invalid record, a changed branch or commit, changed targets or target index, workspaces, and ambiguous lockfiles. Restore the recorded state or recover manually after reviewing the changes. A repeated refresh failure creates a new record if the state is still safe. The record is removed before a retry runs and after success; an interruption or staging failure therefore requires manual inspection and recovery. Once you have recovered manually, remove the record from the worktree's Git directory before starting another version bump. No automatic rollback is performed.

### Configuration

Set before loading the plugin:

| Variable                       | Default   | Description                              |
|--------------------------------|-----------|------------------------------------------|
| `ZSH_VERSION_IT_BRANCH_PREFIX` | `patch`   | Prefix for the created branch name.      |

For example, `ZSH_VERSION_IT_BRANCH_PREFIX=release` creates branches like `release/1.2.4`.

## License

MIT — see [LICENSE](LICENSE).
