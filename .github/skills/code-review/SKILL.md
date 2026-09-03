---
name: code-review
description: Review priorities for zsh-version-it pull requests, what deserves real scrutiny versus what to skip. Use for every PR review.
---

# Review priorities

zsh-version-it is a single ~80-line zsh plugin (`zsh-version-it.plugin.zsh`) that shells out to `npm` and `git`. There's no other source file, so nearly every PR touches the one function that matters: `versionit`.

## Spend real attention here
- `versionit`'s command chain (`npm version` → re-read the version → `git checkout -b` → `npm install --package-lock-only` → `git add .`). The tool's entire premise is "preview, confirm, stage — never commit, never push." Any reordering, added step, or dropped `|| return 1` on one of these calls breaks that contract silently.
- Quoting/escaping of `$1` (the user's version argument) and `${ZSH_VERSION_IT_BRANCH_PREFIX}/${new}` (the branch name). Nothing in this file runs through shellcheck in CI — `codeql.yml`'s own header comment says it scans GitHub Actions workflows only, since no CodeQL analyzer covers zsh — so shell-quoting bugs here aren't caught by any automation.
- The `[[ -t 0 ]]` branch in the confirmation prompt that picks between `read -k 1` and `read -k 1 -u 0`. This already broke once and was fixed in PR #6 (piped stdin crashed the prompt) — any change to the prompt loop deserves a check against both an interactive tty and piped/non-interactive stdin.
- `.github/workflows/*` changes that interpolate untrusted input (PR title, branch name, issue body) directly into a `run:` step — the workflow-injection risk `codeql.yml`'s comment names as the actual threat model for this repo, since it can't scan the shell code itself.

## Do not spend attention here
- README.md, LICENSE — prose only, nothing to review.
- `spec/spec_helper.sh` — stock shellspec harness boilerplate, not repo-specific.
- Routine `.github/workflows/*` edits that are synced templates from `seankoji-com/.github` (recognizable by titles like "sync caller templates") — maintained centrally, not authored per-repo.
- Behavior already pinned by `spec/zsh-version-it_spec.sh`: missing-`package.json` errors, missing-argument errors, abort-on-`n`, the exact preview text, branch naming after the version npm actually wrote, custom `ZSH_VERSION_IT_BRANCH_PREFIX`, and the npm-failure short-circuit. If a PR doesn't change this behavior, check for gaps against these cases instead of re-litigating them.

## Comment style
- One comment per real issue, not one per file it repeats in.
- Skip restating what shellspec or CodeQL already flags — check CI status before commenting on something it would catch.
