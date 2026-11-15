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

# Records are per worktree. They contain hashes and metadata, never file contents.
_versionit_record() {
  node -e '
    const fs = require("fs"), crypto = require("crypto");
    const [file, branch, head, version, lock, manager, dir] = process.argv.slice(1);
    const hash = p => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
    fs.writeFileSync(file, JSON.stringify({format: 1, branch, head, version, lock, manager, dir,
      packageHash: hash("package.json"), lockHash: hash(lock)}), {flag: "wx", mode: 0o600});
  ' "$1" "$2" "$3" "$4" "$5" "$6" "${PWD:A}"
}

_versionit_failed_refresh() {
  local record=$1 branch=$2 head=$3 new=$4 lock=$5 manager=$6 package_hash=$7
  if [[ $(git branch --show-current) == $branch && $(git rev-parse HEAD) == $head ]] &&
     git diff --cached --quiet -- package.json "$lock" &&
     node -e 'const f=require("fs"),c=require("crypto");try {if(c.createHash("sha256").update(f.readFileSync("package.json")).digest("hex")!==process.argv[1])process.exit(1);f.accessSync(process.argv[2])}catch(e){process.exit(1)}' "$package_hash" "$lock" &&
     _versionit_resume_scope "$lock" &&
     _versionit_record "$record" "$branch" "$head" "$new" "$lock" "$manager"; then
    print -u2 'versionit: lockfile update failed; inspect the working tree and run versionit resume'
  else
    print -u2 'versionit: lockfile update failed; no safe recovery record, inspect and recover manually'
  fi
}

# Validate before confirmation and again after confirmation, before consuming the record.
_versionit_validate_record() {
  [[ -f package.json && ! -L package.json ]] || return 1
  node -e '
    const fs = require("fs"), crypto = require("crypto"), cp = require("child_process");
    try {
      const r = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      if (fs.lstatSync(r.lock).isSymbolicLink() || !fs.statSync(r.lock).isFile()) process.exit(1);
      const hash = p => crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
      const git = (...args) => cp.execFileSync("git", args, {encoding:"utf8"}).trim();
      if (r.format !== 1 || r.dir !== process.cwd() ||
          !["package-lock.json", "pnpm-lock.yaml"].includes(r.lock) ||
          r.manager !== (r.lock === "package-lock.json" ? "npm" : "pnpm") ||
          typeof r.branch !== "string" || typeof r.head !== "string" || typeof r.version !== "string" ||
          git("branch", "--show-current") !== r.branch || git("rev-parse", "HEAD") !== r.head ||
          JSON.parse(fs.readFileSync("package.json")).version !== r.version ||
          hash("package.json") !== r.packageHash || hash(r.lock) !== r.lockHash) process.exit(1);
      cp.execFileSync("git", ["ls-files", "--error-unmatch", "--", "package.json", r.lock], {stdio:"ignore"});
      cp.execFileSync("git", ["diff", "--cached", "--quiet", "--", "package.json", r.lock], {stdio:"ignore"});
    } catch (_) { process.exit(1); }
  ' "$1"
}

_versionit_resume_scope() {
  local lock=$1 root ancestor candidate
  if ! node -e 'const p=require(process.cwd()+"/package.json"); process.exit(p.workspaces ? 1 : 0)' || [[ -e pnpm-workspace.yaml ]]; then
    print -u2 'versionit: workspace recovery requires manual review'; return 1
  fi
  root=$(git rev-parse --show-toplevel) || return 1
  ancestor=${PWD:A:h}
  while [[ ${PWD:A} != $root && ( $ancestor == $root || $ancestor == $root/* ) ]]; do
    for candidate in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock pnpm-workspace.yaml package.json; do
      if [[ $candidate == package.json && -f $ancestor/$candidate ]]; then
        node -e 'const p=require(process.argv[1]); process.exit(p.workspaces ? 1 : 0)' "$ancestor/$candidate" || { print -u2 'versionit: ancestor workspace requires manual recovery'; return 1; }
      elif [[ $candidate != package.json && -e $ancestor/$candidate ]]; then
        print -u2 'versionit: ancestor workspace or lockfile requires manual recovery'; return 1
      fi
    done
    [[ $ancestor == $root ]] && break
    ancestor=${ancestor:h}
  done
  for candidate in package-lock.json npm-shrinkwrap.json pnpm-lock.yaml yarn.lock; do
    [[ $candidate == $lock || ! -e $candidate ]] || { print -u2 'versionit: another lockfile requires manual recovery'; return 1; }
  done
}

_versionit_resume() {
  local gitdir claim result
  gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  claim=$gitdir/versionit-resume.lock
  mkdir -- "$claim" 2>/dev/null || { print -u2 "versionit: resume already running or interrupted; inspect $claim"; return 1; }
  {
    _versionit_resume_locked
    result=$?
  } always {
    rmdir -- "$claim" || print -u2 "versionit: could not remove $claim; inspect it manually"
  }
  return $result
}

_versionit_resume_locked() {
  local gitdir record branch head new lock manager reply package_hash result
  gitdir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  record=$gitdir/versionit-resume.json
  if [[ ! -f $record || -L $record ]] || ! _versionit_validate_record "$record"; then
    print -u2 'versionit: recovery state missing or changed; inspect and recover manually'
    return 1
  fi
  branch=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).branch' "$record") || return 1
  head=$(git rev-parse HEAD) || return 1
  new=$(version) || return 1
  lock=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).lock' "$record") || return 1
  manager=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).manager' "$record") || return 1
  package_hash=$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).packageHash' "$record") || return 1
  _versionit_resume_scope "$lock" || return 1
  (( $+commands[$manager] )) || { print -u2 "versionit: $manager is required"; return 1; }
  print "Resume version $new on branch $branch: refresh $lock with $manager (lifecycle scripts disabled), then stage package.json and $lock."
  [[ $manager != pnpm ]] || print 'pnpm may still run .pnpmfile.cjs hooks.'
  print 'Review the current package and lockfile diff before confirming.'
  print 'Existing unrelated changes remain untouched. Nothing is committed or pushed.'
  print -n 'Continue? [y/N] '
  if [[ -t 0 ]]; then
    read -k 1 reply || return 1
  else
    read -k 1 -u 0 reply || return 1
  fi
  print
  [[ $reply == [Yy] ]] || { print 'Aborting'; return 1; }
  _versionit_validate_record "$record" || { print -u2 'versionit: recovery state changed after confirmation'; return 1; }
  _versionit_resume_scope "$lock" || return 1
  # Consume before mutation. A crash or staging failure requires manual recovery.
  rm -- "$record" || return 1
  if [[ $manager == npm ]]; then
    npm install --package-lock-only --ignore-scripts
  else
    pnpm install --lockfile-only --ignore-scripts
  fi
  result=$?
  if [[ $(git branch --show-current) != $branch || $(git rev-parse HEAD) != $head ]] ||
     ! git diff --cached --quiet -- package.json "$lock" ||
     ! node -e 'const f=require("fs"),c=require("crypto");try {if(c.createHash("sha256").update(f.readFileSync("package.json")).digest("hex")!==process.argv[1])process.exit(1);f.accessSync(process.argv[2])}catch(e){process.exit(1)}' "$package_hash" "$lock"; then
    print -u2 'versionit: state changed during refresh; inspect and recover manually'; return 1
  fi
  if (( result != 0 )); then
    _versionit_record "$record" "$branch" "$head" "$new" "$lock" "$manager" || print -u2 'versionit: could not save recovery record; recover manually'
    print -u2 'versionit: lockfile update failed; inspect the working tree and run versionit resume'
    return 1
  fi
  git add -- package.json "$lock" || { print -u2 'versionit: staging failed; inspect the index and recover manually'; return 1; }
  print "Staged version $new on branch $branch"
}

versionit() {
  if (( $# == 1 )) && [[ $1 == resume ]]; then _versionit_resume; return $?; fi
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
  local gitdir record
  gitdir=$(git rev-parse --absolute-git-dir) || return 1
  record=$gitdir/versionit-resume.json
  if [[ -e $record || -L $record || -e $gitdir/versionit-resume.lock ]]; then
    print -u2 "versionit: recovery state exists at $record or $gitdir/versionit-resume.lock; inspect it before continuing"
    return 1
  fi
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
  local new tmp result preid allow_same
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
  local branch head
  [[ ! -e $record && ! -L $record && ! -e $gitdir/versionit-resume.lock ]] || { print -u2 "versionit: recovery state exists at $record or $gitdir/versionit-resume.lock; inspect it before continuing"; return 1; }
  git checkout -b "${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}" || return 1
  branch=$(git branch --show-current) || return 1
  head=$(git rev-parse HEAD) || return 1
  local update_npm_lock=false
  [[ $manager == npm ]] && update_npm_lock=true
  if ! npm version --no-git-tag-version --ignore-scripts --package-lock="$update_npm_lock" "$new"; then
    print -u2 'versionit: version update failed; inspect the branch and working tree'
    return 1
  fi
  local package_hash
  package_hash=$(node -e 'const f=require("fs"),c=require("crypto");process.stdout.write(c.createHash("sha256").update(f.readFileSync("package.json")).digest("hex"))') || return 1
  case $manager in
    npm) if [[ $lock != npm-shrinkwrap.json ]]; then
      npm install --package-lock-only --ignore-scripts || { _versionit_failed_refresh "$record" "$branch" "$head" "$new" "$lock" npm "$package_hash"; return 1; }
    fi ;;
    pnpm) pnpm install --lockfile-only --ignore-scripts || { _versionit_failed_refresh "$record" "$branch" "$head" "$new" "$lock" pnpm "$package_hash"; return 1; } ;;
    yarn) ;;
  esac
  if [[ $lock == npm-shrinkwrap.json ]]; then
    node -e 'const fs = require("fs"); const p = process.argv[1]; const text = fs.readFileSync(p, "utf8"); const lock = JSON.parse(text); const indent = (text.match(/\n([ \t]+)\S/) || [])[1] || ""; const eol = text.includes("\r\n") ? "\r\n" : "\n"; const trailing = /\r?\n$/.test(text) ? eol : ""; lock.version = process.argv[2]; if (lock.packages && lock.packages[""]) lock.packages[""].version = process.argv[2]; fs.writeFileSync(p, JSON.stringify(lock, null, indent).replace(/\n/g, eol) + trailing);' "$lock" "$new" || { print -u2 'versionit: shrinkwrap update failed; inspect the working tree'; return 1; }
  fi
  git add -- "${paths[@]}" || { print -u2 'versionit: staging failed; inspect the branch and working tree'; return 1; }

  print "Staged version ${new} on branch ${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}"
}
