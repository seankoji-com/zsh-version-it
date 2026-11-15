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

  local lock='' manager='' target_file root ancestor candidate ignored_npm_lock=''
  local -a locks paths lock_names
  lock_names=(package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock)
  locks=()
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { print -u2 'versionit: not in a git repository'; return 1 }
  # A Yarn workspace can require a lock update even when its lock is ignored.
  if [[ -f yarn.lock ]] && node -e 'const p = require(process.cwd() + "/package.json"); process.exit(p.workspaces ? 0 : 1)'; then
    print -u2 'versionit: Yarn workspaces require a manual version and lockfile update'
    return 1
  fi
  for candidate in "${lock_names[@]}"; do
    [[ -f $candidate ]] || continue
    if ! git ls-files --error-unmatch -- "$candidate" >/dev/null 2>&1 && git check-ignore -q -- "$candidate"; then
      print -u2 "versionit: ignored $candidate will not be updated or staged; update it manually if needed"
      [[ $candidate == package-lock.json || $candidate == npm-shrinkwrap.json ]] && ignored_npm_lock=$candidate
    else
      locks+=("$candidate")
    fi
  done
  ancestor=${PWD:A:h}
  while [[ ${PWD:A} != $root && ( $ancestor == $root || $ancestor == $root/* ) ]]; do
    for candidate in "${lock_names[@]}"; do
      target_file=$ancestor/$candidate
      [[ -f $target_file ]] || continue
      if git ls-files --error-unmatch -- "$target_file" >/dev/null 2>&1 || ! git check-ignore -q -- "$target_file"; then
        print -u2 'versionit: an ancestor lockfile may cover this package; update it manually'
        return 1
      fi
      print -r -u2 "versionit: ignored $target_file will not be updated or staged; update it manually if needed"
    done
    [[ $ancestor == $root ]] && break
    ancestor=${ancestor:h}
  done
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
  if [[ $manager == npm && -n $ignored_npm_lock ]]; then
    print -u2 "versionit: npm may modify ignored $ignored_npm_lock; update the version and lockfiles manually"
    return 1
  fi
  paths=(package.json)
  [[ -n $lock ]] && paths+=("$lock")
  for target_file in "${paths[@]}"; do
    if ! git ls-files --error-unmatch -- "$target_file" >/dev/null 2>&1 ||
       ! git diff --quiet -- "$target_file" || ! git diff --cached --quiet -- "$target_file"; then
      print -u2 "versionit: $target_file must be tracked and have no staged or unstaged changes"
      return 1
    fi
  done
  [[ -z $manager || $manager == yarn ]] || (( $+commands[$manager] )) || { print -u2 "versionit: $manager is required for $lock"; return 1 }
  if ! git diff --cached --quiet; then
    print -u2 'versionit: existing staged changes will remain staged; review them before committing'
  fi

  print "Updating version ${current} -> ${1}"
  print "Will run:"
  print "    calculate version and git checkout -b ${ZSH_VERSION_IT_BRANCH_PREFIX}/<new version>"
  if [[ $manager == npm ]]; then
    print '    npm version --no-git-tag-version --ignore-scripts --package-lock=true <new version>'
  else
    print '    npm version --no-git-tag-version --ignore-scripts --package-lock=false <new version>'
  fi
  case $manager in
    npm) if [[ $lock == npm-shrinkwrap.json ]]; then
      print '    update npm-shrinkwrap.json root version'
    else
      print '    npm install --package-lock-only --ignore-scripts'
    fi ;;
    pnpm) print '    pnpm install --lockfile-only --ignore-scripts' ;;
    yarn) print '    yarn.lock does not record the root package version; no install needed' ;;
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
  local new tmp result gitdir preid allow_same
  tmp=$(mktemp -d) || return 1
  gitdir=$(git rev-parse --absolute-git-dir) || { rm -rf -- "$tmp"; return 1; }
  preid=$(npm config get preid) || { rm -rf -- "$tmp"; return 1; }
  allow_same=$(npm config get allow-same-version) || { rm -rf -- "$tmp"; return 1; }
  if ! cp -- package.json "$tmp/package.json" ||
     ! (builtin cd "$tmp" && GIT_DIR="$gitdir" GIT_WORK_TREE="$tmp" npm version --no-git-tag-version --ignore-scripts --package-lock=false --preid="$preid" --allow-same-version="$allow_same" "$1" >/dev/null); then
    rm -rf -- "$tmp"
    print -u2 'versionit: could not calculate the new version'
    return 1
  fi
  new=$(node -p "require(process.argv[1]).version" "$tmp/package.json")
  result=$?
  rm -rf -- "$tmp"
  (( result == 0 )) || return 1
  for target_file in "${paths[@]}"; do
    if ! git ls-files --error-unmatch -- "$target_file" >/dev/null 2>&1 ||
       ! git diff --quiet -- "$target_file" || ! git diff --cached --quiet -- "$target_file"; then
      print -u2 "versionit: $target_file changed after confirmation; no branch was created"
      return 1
    fi
  done
  git checkout -b "${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}" || return 1
  local update_npm_lock=false
  [[ $manager == npm ]] && update_npm_lock=true
  if ! npm version --no-git-tag-version --ignore-scripts --package-lock="$update_npm_lock" "$new"; then
    print -u2 'versionit: version update failed; inspect the branch and working tree'
    return 1
  fi
  case $manager in
    npm) if [[ $lock != npm-shrinkwrap.json ]]; then
      npm install --package-lock-only --ignore-scripts || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; }
    fi ;;
    pnpm) pnpm install --lockfile-only --ignore-scripts || { print -u2 'versionit: lockfile update failed; inspect the working tree'; return 1; } ;;
    yarn) ;;
  esac
  if [[ $lock == npm-shrinkwrap.json ]]; then
    node -e 'const fs = require("fs"); const p = process.argv[1]; const text = fs.readFileSync(p, "utf8"); const lock = JSON.parse(text); const indent = (text.match(/\n([ \t]+)\S/) || [])[1] || ""; const eol = text.includes("\r\n") ? "\r\n" : "\n"; const trailing = /\r?\n$/.test(text) ? eol : ""; lock.version = process.argv[2]; if (lock.packages && lock.packages[""]) lock.packages[""].version = process.argv[2]; fs.writeFileSync(p, JSON.stringify(lock, null, indent).replace(/\n/g, eol) + trailing);' "$lock" "$new" || { print -u2 'versionit: shrinkwrap update failed; inspect the working tree'; return 1; }
  fi
  git add -- "${paths[@]}" || { print -u2 'versionit: staging failed; inspect the branch and working tree'; return 1; }

  print "Staged version ${new} on branch ${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}"
}
