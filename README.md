# zsh-version-it

Bump an npm package version onto a fresh branch, ready to commit.

`versionit <keyword|version>` calculates the version with npm, creates a branch named after it, updates `package.json` and the existing lockfile, and stages those files. Nothing is committed or pushed. It asks for confirmation before making changes. Version scripts are disabled. The branch prefix is configurable.

The package and lockfile must be tracked and clean. Multiple lockfiles are rejected instead of guessing which to use. npm handles `package-lock.json` and `npm-shrinkwrap.json`, pnpm handles `pnpm-lock.yaml`, and Yarn handles `yarn.lock`. With no lockfile, none is created. The selected package manager must be installed. If an update fails after branch creation, inspect the working tree before retrying.

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

### Configuration

Set before loading the plugin:

| Variable                       | Default   | Description                              |
|--------------------------------|-----------|------------------------------------------|
| `ZSH_VERSION_IT_BRANCH_PREFIX` | `patch`   | Prefix for the created branch name.      |

For example, `ZSH_VERSION_IT_BRANCH_PREFIX=release` creates branches like `release/1.2.4`.

## License

MIT — see [LICENSE](LICENSE).
