# zsh-version-it

Bump an npm package version onto a fresh branch, ready to commit.

`versionit <keyword|version>` runs `npm version --no-git-tag-version` to update `package.json` (without creating a git tag), then creates a branch named after the resulting version, refreshes the lockfile with `npm install --package-lock-only`, and stages all changes with `git add .`. It stops there — nothing is committed and nothing is pushed, so you review the staged changes and commit yourself. Before doing anything it prints the exact commands it will run and asks for confirmation. The branch prefix is configurable so it can match your team's convention.

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

Requires `node` and `npm` on your `PATH`, and should be run from a git repository containing a `package.json`.

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

`versionit` prints the commands it will run and prompts before making changes. On confirmation it bumps the version, creates a branch (default `patch/<new-version>`), updates the lockfile, and stages everything. The result is left staged for you to review and commit.

### Configuration

Set before loading the plugin:

| Variable                       | Default   | Description                              |
|--------------------------------|-----------|------------------------------------------|
| `ZSH_VERSION_IT_BRANCH_PREFIX` | `patch`   | Prefix for the created branch name.      |

For example, `ZSH_VERSION_IT_BRANCH_PREFIX=release` creates branches like `release/1.2.4`.

## License

MIT — see [LICENSE](LICENSE).
