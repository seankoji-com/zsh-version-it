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
End
