# zsh-version-it — bump an npm package version onto a fresh branch.
#
# `versionit patch` bumps package.json without tagging, cuts a branch named
# after the new version, refreshes the lockfile, and stages everything. It
# stops there: nothing is committed and nothing is pushed.
#
# The branch prefix is configurable, since the useful convention differs per
# team:
#   ZSH_VERSION_IT_BRANCH_PREFIX   default 'patch'

: ${ZSH_VERSION_IT_BRANCH_PREFIX:=patch}

# Print the version from ./package.json.
version() {
  [[ -f package.json ]] || { print -u2 "version: no package.json here"; return 1 }
  node -p "require('./package.json').version"
}

versionit() {
  if [[ ! -f package.json ]]; then
    print -u2 "versionit: no package.json in $PWD"
    return 1
  fi

  if (( $# == 0 )); then
    print -u2 "versionit: specify an npm version keyword or an explicit version"
    print -u2 "  versionit patch | minor | major | 1.12.1"
    return 1
  fi

  local current
  current=$(version) || return 1

  print "Updating version ${current} -> ${1}"
  print "Will run:"
  print "    npm version --no-git-tag-version ${1}"
  print "    git checkout -b ${ZSH_VERSION_IT_BRANCH_PREFIX}/<new version>"
  print "    npm install --package-lock-only"
  print "    git add ."
  print "Changes stay staged. Nothing is committed or pushed."

  local reply=''
  while true; do
    print -n "Continue? [y/N] "
    read -k 1 -u 0 reply
    print
    case $reply in
      [Yy]) break ;;
      [Nn]|$'\n'|'') print "Aborting"; return 1 ;;
      *) print "Please answer y or n" ;;
    esac
  done

  npm version --no-git-tag-version "$1" || return 1

  # Read the version back rather than assuming it: `versionit patch` does not
  # tell you what the result was, and the branch has to be named after the
  # value npm actually wrote.
  local new
  new=$(version) || return 1

  git checkout -b "${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}" || return 1
  npm install --package-lock-only || return 1
  git add . || return 1

  print "Staged version ${new} on branch ${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}"
}
