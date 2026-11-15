# shellcheck shell=bash disable=all
Describe 'zsh-version-it.plugin.zsh'
  Include ./zsh-version-it.plugin.zsh

  setup() {
    TMPROOT="$(mktemp -d)"
    builtin cd "$TMPROOT"
    git init -q
    git config user.name 'Test'
    git config user.email 'test@example.invalid'
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

  It 'does not mutate anything on refusal'
    Data 'n'
    When call versionit patch
    The status should be failure
    The output should include 'Aborting'
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
    run_it() { versionit invalid-version; }
    When call run_it
    The status should be failure
    The output should not include 'Staged version'
    The stderr should include 'could not calculate the new version'
    The contents of file package.json should include '1.2.3'
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
