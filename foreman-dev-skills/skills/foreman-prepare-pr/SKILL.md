---
name: foreman-prepare-pr
description: >
  Prepare a pull request locally without pushing: create a branch, commit
  staged changes, and fill out the repo's PR template into a local file.
  Use when the user says "prepare a PR", "draft a PR locally", "write a PR
  description", or wants to commit and write up a PR body without opening it
  on GitHub.
---

# foreman-prepare-pr skill

Commit changes on a new branch and write a filled-out PR description to a
local file — without pushing or opening a PR on GitHub.

## Step 1 — Assess state and branch

Run in a single parallel batch:

```bash
git status --short
git diff --cached --stat
git diff --stat
git branch --show-current
```

If there are no staged or unstaged changes, tell the user and stop.

If on `develop`, `master` or `main`, create a feature branch from the `--stat` output
(e.g. `add-oauth-lint-rule`, `fix-pulp-volume-mode`):

```bash
git checkout -b <branch-name>
```

## Step 2 — Commit using the commit skill

Invoke the `foreman-commit` skill (`/foreman-commit`) to stage and commit the changes.
It will examine the changes, review recent commit history, draft a
commit message formatted per the seven rules of a great
commit message, and create the commit.

## Step 3 — Find the PR template

Check for a PR template in one compound command:

```bash
cat .github/PULL_REQUEST_TEMPLATE.md 2>/dev/null || cat .github/pull_request_template.md 2>/dev/null || cat docs/pull_request_template.md 2>/dev/null || cat PULL_REQUEST_TEMPLATE.md 2>/dev/null || echo "NO_TEMPLATE"
```

If `NO_TEMPLATE`, use this fallback:

```
#### Summary

#### Test plan
```

## Step 4 — Write the PR description

Gather context — use `--stat` to avoid pulling the full diff into context:

```bash
git log --oneline $(git merge-base HEAD @{upstream} 2>/dev/null || echo HEAD~1)..HEAD
git diff --stat $(git merge-base HEAD @{upstream} 2>/dev/null || echo HEAD~1)...HEAD
```

Fill each template section from the commit messages and stat summary:

- **Summary** — One short paragraph on what was missing, broken, or needed,
  and a tight bullet list of what changed.
- **Test plan** — Concrete steps: exact commands, expected output.
- **Checklist** — Check items that apply, leave others unchecked.

Keep the tone direct. No filler. Do NOT read the full diff to write the
description — the commit messages and stat output have enough context.

Write the filled-out template to `.tmp/pr-description.md` (create `.tmp/`
if needed). Show the user the file path and print the contents.
