# zsh-version-it — bump an npm package version onto a fresh branch.
#
# `versionit patch` bumps package.json without tagging, cuts a branch named
# after the new version, refreshes the existing lockfile, and stages those files. It
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

  if (( $# != 1 )); then
    print -u2 "versionit: specify an npm version keyword or an explicit version"
    print -u2 "  versionit patch | minor | major | 1.12.1"
    return 1
  fi

  local current
  current=$(version) || return 1

  local lock='' manager='' target_file
  local -a locks paths
  locks=()
  [[ -f package-lock.json ]] && locks+=(package-lock.json)
  [[ -f npm-shrinkwrap.json ]] && locks+=(npm-shrinkwrap.json)
  [[ -f pnpm-lock.yaml ]] && locks+=(pnpm-lock.yaml)
  [[ -f yarn.lock ]] && locks+=(yarn.lock)
  if (( ${#locks} > 1 )); then
    print -u2 'versionit: multiple lockfiles found; resolve the ambiguity first'
    return 1
  fi
  lock=${locks[1]:-}
  case $lock in
    package-lock.json|npm-shrinkwrap.json) manager=npm ;;
    pnpm-lock.yaml) manager=pnpm ;;
    yarn.lock) manager=yarn ;;
  esac
  paths=(package.json)
  [[ -n $lock ]] && paths+=("$lock")
  git rev-parse --show-toplevel >/dev/null 2>&1 || { print -u2 'versionit: not in a git repository'; return 1 }
  for target_file in "${paths[@]}"; do
    if ! git ls-files --error-unmatch -- "$target_file" >/dev/null 2>&1 ||
       ! git diff --quiet -- "$target_file" || ! git diff --cached --quiet -- "$target_file"; then
      print -u2 "versionit: $target_file must be tracked and have no staged or unstaged changes"
      return 1
    fi
  done
  [[ -z $manager ]] || (( $+commands[$manager] )) || { print -u2 "versionit: $manager is required for $lock"; return 1 }

  print "Updating version ${current} -> ${1}"
  print "Will run:"
  print "    calculate version and git checkout -b ${ZSH_VERSION_IT_BRANCH_PREFIX}/<new version>"
  print '    npm version --no-git-tag-version --ignore-scripts --package-lock=false <new version>'
  case $manager in
    npm) print '    npm install --package-lock-only --ignore-scripts' ;;
    pnpm) print '    pnpm install --lockfile-only --ignore-scripts' ;;
    yarn) print '    yarn install --ignore-scripts (Yarn 1) or --mode=update-lockfile (Yarn 2+)' ;;
    *) print '    No lockfile to refresh' ;;
  esac
  print "    git add -- ${(j: :)paths}"
  print "Changes stay staged. Nothing is committed or pushed."

  local reply=''
  while true; do
    print -n "Continue? [y/N] "
    if [[ -t 0 ]]; then
      read -k 1 reply
    else
      read -k 1 -u 0 reply
    fi
    print
    case $reply in
      [Yy]) break ;;
      [Nn]|$'\n'|'') print "Aborting"; return 1 ;;
      *) print "Please answer y or n" ;;
    esac
  done

  # Ask npm to resolve keywords in an isolated copy before touching the tree.
  local new tmp result yarn_version
  tmp=$(mktemp -d) || return 1
  if ! cp -- package.json "$tmp/package.json" ||
     ! (builtin cd "$tmp" && npm version --no-git-tag-version --ignore-scripts --package-lock=false "$1" >/dev/null); then
    rm -rf -- "$tmp"
    print -u2 'versionit: could not calculate the new version'
    return 1
  fi
  new=$(node -p "require(process.argv[1]).version" "$tmp/package.json")
  result=$?
  rm -rf -- "$tmp"
  (( result == 0 )) || return 1
  git checkout -b "${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}" || return 1
  if ! npm version --no-git-tag-version --ignore-scripts --package-lock=false "$new"; then
    print -u2 'versionit: version update failed; inspect the branch and working tree'
    return 1
  fi
  case $manager in
    npm) npm install --package-lock-only --ignore-scripts || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; } ;;
    pnpm) pnpm install --lockfile-only --ignore-scripts || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; } ;;
    yarn)
      yarn_version=$(yarn --version) || return 1
      if [[ $yarn_version == 1.* ]]; then
        yarn install --ignore-scripts --non-interactive || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; }
      else
        yarn install --mode=update-lockfile || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; }
      fi ;;
  esac
  git add -- "${paths[@]}" || return 1

  print "Staged version ${new} on branch ${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}"
}
