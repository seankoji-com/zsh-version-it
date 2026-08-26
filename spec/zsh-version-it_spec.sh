# shellcheck shell=bash disable=all
Describe 'zsh-version-it.plugin.zsh'
  Include ./zsh-version-it.plugin.zsh

  setup() {
    TMPROOT="$(mktemp -d)"
    builtin cd "$TMPROOT"
  }
  cleanup() { builtin cd "$SHELLSPEC_PROJECT_ROOT"; rm -rf "$TMPROOT"; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  make_package() { print -r -- "{\"name\":\"x\",\"version\":\"${1:-1.2.3}\"}" > package.json; }

  Describe 'version'
    It 'errors with no package.json'
      When call version
      The status should be failure
      The stderr should include 'no package.json'
    End

    It 'prints the version'
      run_it() { make_package 1.2.3; version; }
      When call run_it
      The output should equal '1.2.3'
    End
  End

  Describe 'versionit argument handling'
    It 'errors with no package.json'
      When call versionit patch
      The status should be failure
      The stderr should include 'no package.json'
    End

    It 'errors with no version argument'
      run_it() { make_package; versionit; }
      When call run_it
      The status should be failure
      The stderr should include 'specify an npm version keyword'
    End
  End

  Describe 'the confirmation prompt'
    # Nothing may run before the operator says yes: the command rewrites
    # package.json and cuts a branch.
    It 'aborts on n without touching anything'
      Data 'n'
      run_it() {
        make_package
        npm() { print -u2 'NPM RAN'; }
        git() { print -u2 'GIT RAN'; }
        versionit patch
      }
      When call run_it
      The status should be failure
      The output should include 'Aborting'
      The stderr should equal ''
    End

    It 'previews the exact commands before asking'
      Data 'n'
      run_it() { make_package 1.2.3; versionit minor; }
      When call run_it
      The output should include 'npm version --no-git-tag-version minor'
      The output should include 'npm install --package-lock-only'
      The output should include 'Updating version 1.2.3 -> minor'
      The status should be failure
    End

    It 'says plainly that nothing is committed or pushed'
      Data 'n'
      run_it() { make_package; versionit patch; }
      When call run_it
      The output should include 'Nothing is committed or pushed'
      The status should be failure
    End
  End

  Describe 'the happy path'
    # The branch has to be named after the version npm actually wrote, which
    # is not derivable from the keyword the user typed.
    It 'names the branch after the resulting version'
      Data 'y'
      run_it() {
        make_package 1.2.3
        npm() {
          [[ "$1" == version ]] && make_package 1.3.0
          return 0
        }
        git() { print "git $*"; }
        versionit minor
      }
      When call run_it
      The output should include 'git checkout -b patch/1.3.0'
      The output should include 'Staged version 1.3.0'
    End

    It 'honours a custom branch prefix'
      Data 'y'
      run_it() {
        ZSH_VERSION_IT_BRANCH_PREFIX=release
        make_package 1.2.3
        npm() { [[ "$1" == version ]] && make_package 2.0.0; return 0; }
        git() { print "git $*"; }
        versionit major
      }
      When call run_it
      The output should include 'git checkout -b release/2.0.0'
    End

    It 'stops when npm version fails'
      Data 'y'
      run_it() {
        make_package
        npm() { return 1; }
        git() { print -u2 'GIT RAN'; }
        versionit patch
      }
      When call run_it
      The status should be failure
      # git must not have been reached.
      The stderr should equal ''
      The output should include 'Continue?'
      The output should not include 'Staged version'
    End
  End
End
