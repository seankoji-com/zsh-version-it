# shellcheck shell=bash disable=all
Describe 'zsh-version-it.plugin.zsh'
  Include ./zsh-version-it.plugin.zsh

  setup() {
    TMPROOT="$(mktemp -d)"
    builtin cd "$TMPROOT"
    git init -q
    git config user.name 'Test'
    git config user.email 'test@example.invalid'
    git config commit.gpgsign false
    git config core.hooksPath /dev/null
    print '{"name":"versionit-test","version":"1.2.3"}' > package.json
    git add package.json
    git commit -qm initial
  }
  cleanup() { builtin cd "$SHELLSPEC_PROJECT_ROOT"; rm -rf "$TMPROOT"; }
  missing_pnpm() { ! command -v pnpm >/dev/null 2>&1; }
  missing_yarn() { ! command -v yarn >/dev/null 2>&1; }
  unrelated_changes() {
    print 'original' > unrelated
    git add unrelated && git commit -qm unrelated || return
    print 'staged' > unrelated
    git add unrelated || return
    print 'unstaged' >> unrelated
    print 'untracked data' > untracked
    original_branch=$(git branch --show-current)
    original_index=$(git write-tree)
    original_diff=$(git diff --binary | git hash-object --stdin)
  }
  unrelated_preserved() {
    [[ $(git write-tree) == $original_index &&
       $(git diff --binary -- unrelated | git hash-object --stdin) == $original_diff &&
       $(<untracked) == 'untracked data' ]]
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It 'prints the current version'
    When call version
    The output should equal '1.2.3'
  End

  It 'reports a missing package for both commands'
    run_it() { rm package.json; version; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'version: no package.json'
    The stderr should include 'versionit: no package.json'
  End

  It 'requires a version argument'
    When call versionit
    The status should be failure
    The stderr should include 'specify an npm version keyword'
  End

  It 'rejects multiple arguments'
    When call versionit patch extra
    The status should be failure
    The stderr should include 'specify an npm version keyword'
  End

  It 'does not mutate anything on refusal'
    Data 'n'
    run_it() { versionit patch && return 2; git branch --list 'patch/*'; return 1; }
    When call run_it
    The status should be failure
    The output should include 'Aborting'
    The output should include 'Nothing is committed or pushed'
    The output should include 'git checkout -b'
    The output should include 'npm version --no-git-tag-version'
    The output should include 'git add -- package.json'
    The output should not include 'patch/1.2.4'
    The contents of file package.json should include '1.2.3'
  End

  It 'creates the branch and stages only the package, preserving unrelated changes'
    Data 'y'
    run_it() {
      print 'before' > unrelated
      git add unrelated
      git commit -qm unrelated
      print 'staged' > unrelated
      git add unrelated
      print 'unstaged' >> unrelated
      print 'new' > untracked
      versionit patch || return
      print "BRANCH=$(git branch --show-current)"
      print "STAGED=$(git diff --cached --name-only | tr '\n' ',')"
      print "UNSTAGED=$(git diff --name-only)"
      [[ ! -e package-lock.json && -f untracked ]]
    }
    When call run_it
    The status should be success
    The output should include 'BRANCH=patch/1.2.4'
    The output should include 'STAGED=package.json,unrelated,'
    The output should include 'UNSTAGED=unrelated'
    The stderr should include 'Switched to a new branch'
    The stderr should include 'existing staged changes will remain staged'
    The contents of file package.json should include '1.2.4'
  End

  It 'does not bump the package when the branch already exists'
    Data 'y'
    run_it() { git branch patch/1.2.4; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'already exists'
    The output should include 'Continue?'
    The contents of file package.json should include '1.2.3'
  End

  It 'honours a custom branch prefix'
    Data 'y'
    run_it() { ZSH_VERSION_IT_BRANCH_PREFIX=release; versionit minor || return; git branch --show-current; }
    When call run_it
    The status should be success
    The output should include 'release/1.3.0'
    The stderr should include 'Switched to a new branch'
  End

  It 'rejects invalid versions without creating a branch or changing the package'
    Data 'y'
    run_it() { versionit invalid-version && return 2; git branch --list 'patch/*'; return 1; }
    When call run_it
    The status should be failure
    The output should not include 'Staged version'
    The output should not include 'patch/1.2.4'
    The stderr should include 'could not calculate the new version'
    The contents of file package.json should include '1.2.3'
  End

  It 'uses the latest git tag for from-git'
    Data 'y'
    run_it() { git tag v1.5.0; versionit from-git; }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.5.0'
    The stderr should include 'Switched to a new branch'
  End

  It 'uses the project prerelease identifier'
    Data 'y'
    run_it() { print 'preid=rc' > .npmrc; versionit prerelease; }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4-rc.0'
    The stderr should include 'Switched to a new branch'
  End

  It 'honours allow-same-version in project configuration'
    Data 'y'
    run_it() { print 'allow-same-version=true' > .npmrc; versionit 1.2.3; }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.3'
    The stderr should include 'Switched to a new branch'
  End

  It 'reports a version failure after checkout'
    Data 'y'
    run_it() {
      npm() {
        if [[ $1 == version && "$PWD" == "$TMPROOT" ]]; then return 1; fi
        command npm "$@"
      }
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'version update failed'
    The output should not include 'Staged version'
  End

  It 'refuses a package changed after confirmation'
    Data 'y'
    run_it() {
      npm() {
        if [[ $1 == config && $3 == preid ]]; then print ' ' >> "$TMPROOT/package.json"; fi
        command npm "$@"
      }
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'changed after confirmation; no branch was created'
    The output should include 'Continue?'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses a package below an ancestor lockfile before changing it'
    run_it() {
      mkdir -p packages/a
      print '{"name":"a","version":"1.2.3"}' > packages/a/package.json
      touch package-lock.json
      git add package-lock.json packages/a/package.json && git commit -qm workspace
      builtin cd packages/a
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'ancestor lockfile'
    The contents of file "$TMPROOT/packages/a/package.json" should include '1.2.3'
  End

  It 'ignores an untracked ignored ancestor lockfile'
    Data 'y'
    run_it() {
      mkdir -p packages/a
      print '{"name":"a","version":"1.2.3"}' > packages/a/package.json
      print '/yarn.lock' > .gitignore
      print 'ancestor data' > yarn.lock
      git add packages/a/package.json && git commit -qm package
      builtin cd packages/a
      versionit patch || return
      [[ $(cat "$TMPROOT/yarn.lock") == 'ancestor data' ]] || return 1
      git diff --cached --name-only
    }
    When call run_it
    The status should be success
    The output should include 'packages/a/package.json'
    The stderr should include 'ignored '
    The stderr should include 'yarn.lock will not be updated or staged'
    The stderr should include 'Switched to a new branch'
    The contents of file "$TMPROOT/yarn.lock" should equal 'ancestor data'
  End

  It 'preserves backslashes in an ignored ancestor lockfile warning'
    Data 'y'
    run_it() {
      mkdir -p 'dir\t/package'
      print '{"name":"a","version":"1.2.3"}' > 'dir\t/package/package.json'
      print '/dir*/yarn.lock' > .gitignore
      print 'ancestor data' > 'dir\t/yarn.lock'
      git add 'dir\t/package/package.json' && git commit -qm package
      builtin cd 'dir\t/package'
      versionit patch
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The stderr should include "versionit: ignored $TMPROOT/dir\\t/yarn.lock will not be updated or staged; update it manually if needed"
    The contents of file "$TMPROOT/dir\t/yarn.lock" should equal 'ancestor data'
    The contents of file "$TMPROOT/dir\t/package/package.json" should include '1.2.4'
  End

  It 'still refuses an ancestor lockfile tracked despite an ignore pattern'
    run_it() {
      mkdir -p packages/a
      print '{"name":"a","version":"1.2.3"}' > packages/a/package.json
      print '/yarn.lock' > .gitignore
      touch yarn.lock
      git add -f yarn.lock && git add packages/a/package.json && git commit -qm workspace
      builtin cd packages/a
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'ancestor lockfile'
    The contents of file "$TMPROOT/packages/a/package.json" should include '1.2.3'
  End

  It 'reports a staging failure after creating the branch'
    Data 'y'
    run_it() { git() { [[ $1 == add ]] && return 1; command git "$@"; }; versionit patch; }
    When call run_it
    The status should be failure
    The output should not include 'Staged version'
    The stderr should include 'staging failed'
    The stderr should include 'Switched to a new branch'
  End

  It 'stops and reports a lockfile update failure without staging the package'
    Data 'y'
    run_it() {
      npm install --package-lock-only --ignore-scripts >/dev/null || return
      git add package-lock.json && git commit -qm lock
      npm() { if [[ $1 == install ]]; then return 1; else command npm "$@"; fi; }
      versionit patch && return 1
      git diff --cached --quiet || return 2
      print 'index clean'
      return 1
    }
    When call run_it
    The status should be failure
    The output should not include 'Staged version'
    The output should include 'index clean'
    The stderr should include 'lockfile update failed'
    The stderr should include 'Switched to a new branch'
  End

  It 'refuses to overwrite a pre-existing package edit'
    run_it() { print ' ' >> package.json; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'must be tracked and have no staged or unstaged changes'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses a staged package edit without changing the index'
    run_it() { print ' ' >> package.json; git add package.json; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'must be tracked and have no staged or unstaged changes'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses an untracked lockfile without changing it'
    run_it() { print 'user data' > package-lock.json; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'must be tracked and have no staged or unstaged changes'
    The contents of file package-lock.json should equal 'user data'
  End

  It 'leaves an ignored lockfile untouched and warns'
    Data 'y'
    run_it() {
      print 'package-lock.json' > .gitignore
      print 'local data' > package-lock.json
      versionit patch || return
      [[ $(cat package-lock.json) == 'local data' ]] || return 1
      git diff --cached --name-only
    }
    When call run_it
    The status should be success
    The stderr should include 'ignored package-lock.json will not be updated or staged'
    The output should include 'package.json'
    The contents of file package-lock.json should equal 'local data'
  End

  It 'does not count an ignored untracked lockfile against a tracked lockfile'
    Data 'y'
    run_it() {
      npm install --package-lock-only --ignore-scripts >/dev/null || return
      git add package-lock.json && git commit -qm lock
      print 'yarn.lock' > .gitignore
      print 'local data' > yarn.lock
      versionit patch || return
      [[ $(cat yarn.lock) == 'local data' ]] || return 1
      node -e 'if(require("./package-lock.json").version!=="1.2.4") process.exit(1)' || return
      git diff --cached --name-only
    }
    When call run_it
    The status should be success
    The stderr should include 'ignored yarn.lock will not be updated or staged'
    The output should include 'package-lock.json'
    The contents of file yarn.lock should equal 'local data'
  End

  It 'leaves an ignored npm lockfile alone beside a tracked Yarn lockfile'
    Data 'y'
    run_it() {
      print 'tracked yarn' > yarn.lock
      git add yarn.lock && git commit -qm lock
      print 'package-lock.json' > .gitignore
      print 'local data' > package-lock.json
      versionit patch || return
      [[ $(cat package-lock.json) == 'local data' && $(cat yarn.lock) == 'tracked yarn' ]] || return 1
      git diff --cached --name-only
    }
    When call run_it
    The status should be success
    The stderr should include 'ignored package-lock.json will not be updated or staged'
    The output should include 'package.json'
    The contents of file package-lock.json should equal 'local data'
  End

  It 'counts tracked lockfiles even when ignore patterns match them'
    run_it() {
      print 'yarn.lock' > .gitignore
      touch yarn.lock pnpm-lock.yaml
      git add -f yarn.lock && git add pnpm-lock.yaml && git commit -qm locks
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'multiple lockfiles'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses a Yarn workspace even when its lockfile is ignored'
    run_it() {
      print '{"name":"versionit-test","version":"1.2.3","workspaces":["packages/*"]}' > package.json
      git add package.json && git commit -qm workspace
      print 'yarn.lock' > .gitignore
      print 'local data' > yarn.lock
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'Yarn workspaces require a manual version and lockfile update'
    The contents of file yarn.lock should equal 'local data'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses conflicting npm lockfiles when one is ignored'
    run_it() {
      npm install --package-lock-only --ignore-scripts >/dev/null || return
      git add package-lock.json && git commit -qm lock
      print 'npm-shrinkwrap.json' > .gitignore
      print 'local data' > npm-shrinkwrap.json
      versionit patch
    }
    When call run_it
    The status should be failure
    The stderr should include 'npm may modify ignored npm-shrinkwrap.json'
    The contents of file npm-shrinkwrap.json should equal 'local data'
    The contents of file package.json should include '1.2.3'
  End

  It 'updates npm shrinkwrap when it exists'
    Data 'y'
    run_it() {
      npm install --package-lock-only --ignore-scripts >/dev/null || return
      mv package-lock.json npm-shrinkwrap.json || return
      git add npm-shrinkwrap.json && git commit -qm shrinkwrap
      versionit patch || return
      node -e 'console.log("SHRINKWRAP="+require("./npm-shrinkwrap.json").version); if(require("./npm-shrinkwrap.json").version!=="1.2.4") process.exit(1)' || return
      [[ ! -e package-lock.json ]]
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The output should include 'SHRINKWRAP=1.2.4'
    The stderr should include 'Switched to a new branch'
  End

  It 'preserves shrinkwrap indentation and line endings'
    Data 'y'
    run_it() {
      printf '{\r\n    "name": "versionit-test",\r\n    "version": "1.2.3",\r\n    "lockfileVersion": 3,\r\n    "packages": {\r\n        "": {\r\n            "version": "1.2.3"\r\n        }\r\n    }\r\n}\r\n' > npm-shrinkwrap.json
      git add npm-shrinkwrap.json && git commit -qm shrinkwrap
      versionit patch || return
      node -e 'const s=require("fs").readFileSync("npm-shrinkwrap.json","utf8"); if(!s.includes("\r\n    \"version\": \"1.2.4\"") || /(?<!\r)\n/.test(s)) process.exit(1)'
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The stderr should include 'Switched to a new branch'
  End

  It 'updates an existing npm lockfile without staging unrelated files'
    Data 'y'
    run_it() {
      npm install --package-lock-only --ignore-scripts >/dev/null || return
      git add package-lock.json && git commit -qm lock
      print 'untracked' > untracked
      versionit patch || return
      print "STAGED=$(git diff --cached --name-only | tr '\n' ',')"
      node -e 'const l=require("./package-lock.json"); if(l.version!=="1.2.4" || l.packages[""].version!=="1.2.4") process.exit(1)'
    }
    When call run_it
    The status should be success
    The output should include 'STAGED=package-lock.json,package.json,'
    The stderr should include 'Switched to a new branch'
  End

  It 'uses pnpm for an existing pnpm lockfile without creating an npm lockfile'
    Skip if 'pnpm is not installed' missing_pnpm
    Data 'y'
    run_it() {
      pnpm install --lockfile-only --ignore-scripts >/dev/null || return
      git add pnpm-lock.yaml && git commit -qm lock
      versionit patch || return
      [[ ! -e package-lock.json && -f pnpm-lock.yaml ]]
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The stderr should include 'Switched to a new branch'
  End

  It 'dispatches the pnpm lockfile refresh without relying on an installed pnpm'
    Data 'y'
    run_it() {
      mkdir bin
      print '#!/bin/sh' > bin/pnpm
      print 'printf "%s\n" "$*" > "$PNPM_CALLS"' >> bin/pnpm
      chmod +x bin/pnpm
      export PNPM_CALLS="$TMPROOT/pnpm-calls"
      PATH="$TMPROOT/bin:$PATH"
      print 'lockfileVersion: 9' > pnpm-lock.yaml
      git add pnpm-lock.yaml && git commit -qm lock
      versionit patch || return
      [[ ! -e package-lock.json ]]
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The stderr should include 'Switched to a new branch'
    The contents of file "$TMPROOT/pnpm-calls" should equal 'install --lockfile-only --ignore-scripts'
  End

  It 'uses yarn for an existing yarn lockfile without creating an npm lockfile'
    Skip if 'yarn is not installed' missing_yarn
    Data 'y'
    run_it() {
      yarn install --ignore-scripts --non-interactive >/dev/null || return
      git add yarn.lock && git commit -qm lock
      versionit patch || return
      [[ ! -e package-lock.json && -f yarn.lock ]]
    }
    When call run_it
    The status should be success
    The output should include 'Staged version 1.2.4'
    The stderr should include 'Switched to a new branch'
  End

  It 'refuses ambiguous lockfiles before mutation'
    run_it() { touch yarn.lock pnpm-lock.yaml; versionit patch; }
    When call run_it
    The status should be failure
    The stderr should include 'multiple lockfiles'
    The contents of file package.json should include '1.2.3'
  End

  It 'refuses a missing required pnpm before changing branch, index or worktree'
    run_it() {
      local PATH="$PATH"
      print 'lockfileVersion: 9' > pnpm-lock.yaml
      git add pnpm-lock.yaml && git commit -qm lock || return
      unrelated_changes || return
      mkdir bin
      ln -s "$(command -v git)" bin/git
      ln -s "$(command -v node)" bin/node
      PATH="$TMPROOT/bin"
      versionit patch
      result=$?
      [[ $result == 1 && $(git branch --show-current) == $original_branch ]] || return 2
      unrelated_preserved || return 3
      [[ $(git status --porcelain -- package.json pnpm-lock.yaml) == '' ]] || return 4
      [[ -z $(git branch --list 'patch/*') ]] || return 5
      return $result
    }
    When call run_it
    The status should equal 1
    The stderr should include 'pnpm is required for pnpm-lock.yaml'
    The output should not include 'Continue?'
    The contents of file package.json should include '1.2.3'
    The contents of file pnpm-lock.yaml should equal 'lockfileVersion: 9'
  End

  It 'refuses a tracked Yarn workspace root without changing any state'
    run_it() {
      print '{"name":"versionit-test","version":"1.2.3","workspaces":["packages/*"]}' > package.json
      print 'tracked yarn lock' > yarn.lock
      git add package.json yarn.lock && git commit -qm workspace || return
      unrelated_changes || return
      versionit patch
      result=$?
      [[ $result == 1 && $(git branch --show-current) == $original_branch ]] || return 2
      unrelated_preserved || return 3
      [[ $(git status --porcelain -- package.json yarn.lock) == '' ]] || return 4
      [[ -z $(git branch --list 'patch/*') ]] || return 5
      return $result
    }
    When call run_it
    The status should equal 1
    The stderr should include 'Yarn workspaces require a manual version and lockfile update'
    The output should not include 'Continue?'
    The contents of file package.json should include '1.2.3'
    The contents of file yarn.lock should equal 'tracked yarn lock'
  End

  It 'refuses invocation outside Git while preserving the existing repository'
    run_it() {
      unrelated_changes || return
      mkdir outside
      print '{"name":"outside","version":"1.2.3"}' > outside/package.json
      builtin cd outside
      GIT_CEILING_DIRECTORIES="$TMPROOT" versionit patch
      result=$?
      builtin cd "$TMPROOT"
      [[ $result == 1 && $(git branch --show-current) == $original_branch ]] || return 2
      unrelated_preserved || return 3
      [[ $(git status --porcelain -- package.json) == '' ]] || return 4
      [[ -z $(git branch --list 'patch/*') ]] || return 5
      return $result
    }
    When call run_it
    The status should equal 1
    The stderr should include 'not in a git repository'
    The output should not include 'Continue?'
    The contents of file "$TMPROOT/outside/package.json" should equal '{"name":"outside","version":"1.2.3"}'
  End

  It 'reports a shrinkwrap write failure after checkout without staging the bump'
    Data 'y'
    run_it() {
      print '{"name":"versionit-test","version":"1.2.3","lockfileVersion":3,"packages":{"":{"name":"versionit-test","version":"1.2.3"}}}' > npm-shrinkwrap.json
      git add npm-shrinkwrap.json && git commit -qm shrinkwrap || return
      unrelated_changes || return
      node() {
        if [[ $1 == -e && $3 == npm-shrinkwrap.json ]]; then return 73; fi
        command node "$@"
      }
      versionit patch
      result=$?
      [[ $result == 1 && $(git branch --show-current) == patch/1.2.4 ]] || return 2
      unrelated_preserved || return 3
      [[ $(git diff --cached --name-only) == unrelated ]] || return 4
      [[ $(git diff --name-only -- package.json) == package.json ]] || return 5
      [[ $(git status --porcelain -- npm-shrinkwrap.json) == '' ]] || return 6
      return $result
    }
    When call run_it
    The status should equal 1
    The stderr should include 'shrinkwrap update failed; inspect the working tree'
    The output should not include 'Staged version'
    The contents of file package.json should include '1.2.4'
  End
End
