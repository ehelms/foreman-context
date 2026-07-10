---
name: foreman-plugin-release
description: Use when releasing a Foreman plugin gem - bumping version, tagging, pushing to rubygems, and updating upstream/downstream packaging
---

# Foreman Plugin Release

## Overview

Release process for Foreman plugins: bump version in-repo, tag, push (triggers rubygems publish via GitHub Actions), then trigger packaging updates.

## Steps

### 1a. Prepare and Determine Version

```bash
# The upstream remote may not be called "upstream" — find the one under theforeman org
git remote -v | grep theforeman
# Use that remote name in place of "upstream" below

git fetch <upstream-remote>

# Detect the default branch (commonly develop, master, or main)
git remote show <upstream-remote> | grep 'HEAD branch'
# Use that branch name in place of <default-branch> below

# Create a worktree based on <upstream-remote>/<default-branch> to keep the main working directory clean
git worktree add /tmp/<plugin_name>-release <upstream-remote>/<default-branch>
cd /tmp/<plugin_name>-release
```

If the repository contains a `RELEASE.md`, read it first and honor any conventions it establishes — it may override or extend the defaults described here.

Read the current version from `lib/<plugin_name>/version.rb` and recent commits/changelog to determine what changed since the last release. Apply versioning rules (see below) to propose the next version.

**STOP: Present the suggested version to the user and wait for explicit approval before proceeding.**

### 1b. Bump, Tag, Push, and Clean Up

```bash
# Working inside /tmp/<plugin_name>-release

# Bump version file (lib/<plugin_name>/version.rb)
# Edit VERSION = "x.y.z"

# Determine the tag format — check existing tags to see if the repo uses a "v" prefix or bare version numbers
git tag | sort -V | tail -5
# Use the same prefix convention as existing tags

git add lib/<plugin_name>/version.rb
git commit -m "Bump version to x.y.z"
git tag -a <tag> -m "Release <tag>"   # e.g. v1.2.3 or 1.2.3 depending on the repo convention; always use annotated tags (-a)
# Push HEAD and the annotated tag together; --follow-tags pushes annotated tags reachable from the pushed commits
git push --follow-tags <upstream-remote> HEAD:<default-branch>

# Remove the worktree
cd -
git worktree remove /tmp/<plugin_name>-release
```

### 2. RubyGems (automatic + verify)

Tag push triggers GitHub Actions release workflow → gem built and pushed to rubygems.org.

**Verify it worked** — either check GitHub Actions:
```bash
gh run list --repo theforeman/<plugin_name> --workflow release.yml --limit 5
gh run watch <run-id> --repo theforeman/<plugin_name>
```

Or poll rubygems.org directly:
```bash
# Replace gem name and version as appropriate
curl -s https://rubygems.org/api/v1/versions/<gem_name>.json | \
  python3 -c "import sys,json; vs=[v['number'] for v in json.load(sys.stdin)]; print('Found' if 'x.y.z' in vs else 'NOT found')"
```

Don't proceed to upstream packaging until the gem is confirmed on rubygems.org.

### 3. Upstream Packaging

Automation runs twice weekly comparing packaging vs rubygems. To trigger manually:

```bash
gh workflow run bump_packages.yml \
  --repo theforeman/foreman-packaging \
  -f package=MyPackageHere
```

After triggering, wait for the workflow run to complete, then find and present the PRs it created:
```bash
# Find the run that was just triggered
gh run list --repo theforeman/foreman-packaging --workflow bump_packages.yml --limit 5
# Watch it to completion
gh run watch <run-id> --repo theforeman/foreman-packaging

# Once the run finishes, find the PRs it opened (usually two: rpm + deb)
gh pr list --repo theforeman/foreman-packaging \
  --search "<gem_name>" --state all \
  --json number,title,url,state,mergedAt
```

Present the PR links to the user. Merge permission matches source repo permissions.

## Versioning Rules

| Change | Version bump |
|--------|-------------|
| Foreman dependency version requirement changes | Major |
| Required Ruby version changes | Major |
| New features | Minor |
| Bug fixes | Patch |

## Common Mistakes

- Forgetting to push the tag (`git push upstream vx.y.z`) — rubygems publish won't trigger
- Pushing tag before the version bump commit — tag should point to the bump commit
- Targeting all packages in packaging workflow — prefer targeting individual packages with `package=` filter
- Using `rubygem-` prefix in the `package=` parameter — that's RPM-specific; use the bare gem name
- The `package=` value is usually the gem name (with underscores), but foreman-tasks is an exception: use `foreman-tasks` (dashes), not `foreman_tasks`
