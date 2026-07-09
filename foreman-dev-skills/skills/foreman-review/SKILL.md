---
name: foreman-review
description: Comprehensive PR review following Foreman project standards - automated convention checks and AI-based code quality assessment
---

# Foreman PR Review

Perform a comprehensive review of the current branch's changes following Foreman project standards.

## Step 1: Setup

Detect the project type by checking whether the following marker files exist:
- **Core**: `app/registries/foreman/plugin.rb` exists
- **Plugin**: `*.gemspec` matching `foreman_*` and `Foreman::Plugin.register` in `lib/`
- **Smart Proxy**: `smart_proxy*.gemspec`

Use `ls *.gemspec` if you need to find gemspec filenames.

### Determining the diff range

The review must cover **only the commits on the current branch that are not in
the upstream main branch**. Detect the base branch by running these commands
(they use only simple git calls — no shell variables):

```bash
git symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null || git symbolic-ref --short refs/remotes/origin/HEAD
```

This returns the base branch (e.g. `origin/develop`). Use it as `BASE_BRANCH`. Then run:

```bash
git merge-base <BASE_BRANCH> HEAD
```

This returns the `MERGE_BASE` SHA. Then list commits and changed files:

```bash
git log --oneline --no-color <MERGE_BASE>..HEAD
```
```bash
git diff --name-only <MERGE_BASE>..HEAD
```

Replace `<BASE_BRANCH>` and `<MERGE_BASE>` with the literal values from the
previous commands. Save `MERGE_BASE` for use in subsequent steps.

**Only review changes from these commits.** Do not include commits already in
the upstream main branch.

**Important:** Do not run `git diff $MERGE_BASE..HEAD` to load the full diff
into context. Use targeted queries in subsequent steps to minimize token usage.

## Step 2: Convention Checks

Run **all** convention checks in a **single bash invocation** using the script
below. Replace `<MERGE_BASE>` with the literal SHA from Step 1 — do **not**
use shell variables. Report any matches before proceeding.

```bash
echo "=== 1. Commit format (must match Fixes|Refs #NNN) ==="
git log --oneline --no-color <MERGE_BASE>..HEAD | grep -v -E '^[a-f0-9]+ (Fixes|Refs) #[0-9]+' || echo "PASS"

echo "=== 2. View extensions (new .erb missing format prefix) ==="
git diff --no-color --diff-filter=A <MERGE_BASE>..HEAD --name-only -- 'app/views/**/*.erb' | grep -v '\.html\.erb$' || echo "PASS"

echo "=== 3. Exception types (must inherit Foreman::Exception) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*class.*Exception.*<' | grep -v 'Foreman::Exception' || echo "PASS"

echo "=== 4. Logger blocks (interpolation without block form) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*logger\.(debug|info).*#\{' || echo "PASS"

echo "=== 5. Concern pattern (class_eval instead of ActiveSupport::Concern) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*class_eval' || echo "PASS"

echo "=== 6. app/ vs lib/ (new service/model classes in lib/) ==="
git diff --no-color --diff-filter=A <MERGE_BASE>..HEAD --name-only -- 'lib/**/*.rb' | grep -E '(service|model)' | grep -v -E '(engine|tasks|generators)' || echo "PASS"

echo "=== 7. Unsafe reflection (.to_sym/.send on params) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*params.*\.(to_sym|send)\(' || echo "PASS"

echo "=== 8. scoped_search (:ext_method without :only_explicit) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*scoped_search.*:ext_method' | grep -v ':only_explicit.*=>.*true' || echo "PASS"

echo "=== 9. Deprecation (ActiveSupport::Deprecation instead of Foreman::Deprecation) ==="
git diff --no-color <MERGE_BASE>..HEAD | grep -E '^\+.*ActiveSupport::Deprecation' || echo "PASS"

echo "=== 10. i18n (user-facing strings without _() wrapping) ==="
echo "Requires contextual review — see AI Assessment below."
```

**Check 10 (i18n)** requires context to distinguish user-facing from internal
strings. During the AI assessment (Step 3), look for added strings in views
(`.erb`) and controllers that lack `_()` wrapping, especially in `flash`,
`render`, `redirect_to` messages, and error messages.

Report all findings from this phase before proceeding.

## Step 3: AI-Based Assessment

**Use the changed files list from Step 1 to decide which checks to run.**
Skip any check whose trigger condition does not match the changed files.
Mark skipped checks as "SKIP — no relevant files changed" in the report.

For checks you do run, examine only the relevant portions of the diff and
surrounding code using targeted `git diff`/`git show`/`git log` commands for
specific files. Only report findings where you have evidence — do not speculate.

### 3.1 Does the PR address the stated issue?
**Always run.**

Read the commit messages to find the `Fixes #XXXX` or `Refs #XXXX` reference.
Assess whether the changes plausibly address the title's description. Flag if:
- The diff appears unrelated to the commit message description
- The change scope seems too narrow or too broad for the stated fix

### 3.2 Unrelated changes
**Always run.**

Look for files or hunks that don't relate to the primary purpose. Flag:
- Whitespace-only changes in unrelated files
- Style-only refactors mixed with bug fixes
- Opportunistic cleanups that should be separate PRs

### 3.3 Test coverage
**Run when:** changed files include `app/` or `lib/` code (not just tests, views, or config).

For each new public method, controller action, or significant behavior change:
- Check if there is a corresponding test in `test/` (Ruby) or `__tests__/` (JS)
- For Ruby: look in `test/models/`, `test/controllers/`, `test/functional/`,
  `test/integration/`, or `test/graphql/` matching the changed file
- For JS: look for `*.test.js` files alongside or under `__tests__/`
- Flag new behavior without any test coverage
- Note: "tests exist" is different from "tests are meaningful" — look at
  what the tests actually assert

### 3.4 Permissions for non-admin users
**Run when:** changed files include `app/controllers/`.

If the diff adds new controller actions:
- Check for `authorize` calls or `before_action :find_resource`
- Look for permission definitions in the plugin's `security_block` or
  in `app/registries/foreman/access_control.rb`
- Flag new actions that lack authorization checks

For core: also check `app/models/permission.rb` data.
For plugins: check the `Foreman::Plugin.register` block for `permission` calls.

### 3.5 ActiveRecord validators on new fields
**Run when:** changed files include `db/migrate/`.

If `db/migrate/` files add new columns:
- Identify the corresponding model file
- Check for `validates` declarations covering the new fields
- Pay special attention to NOT NULL columns that lack presence validators
- Flag missing validators

### 3.6 Exception handling
**Run when:** changed files include `.rb` files under `app/` or `lib/`.

Look for `rescue` blocks in the diff that may swallow exceptions:
- `rescue => e` followed by `nil`, empty block, or only logging at info level
- `rescue StandardError` that returns a generic error without details
- Missing `rescue` in blocks that call external services (API calls, file I/O)

Flag blocks that silently swallow errors without logging or re-raising.

### 3.7 Apipie documentation
**Run when:** changed files include `app/controllers/api/`.

If new API controller actions are added (under `app/controllers/api/`):
- Check for `api :METHOD, path, description` declarations
- Verify `param` declarations match the action's actual parameters
- Check `:required => true/false` accuracy
- Flag undocumented API endpoints

### 3.8 API backward compatibility
**Run when:** changed files include `app/controllers/api/`.

If existing API endpoints are modified:
- Check for removed parameters
- Check for changed response structure (renamed keys, removed fields)
- Check for changed HTTP methods or routes
- These should use `Foreman::Deprecation.api_deprecation_warning` before removal
- Flag breaking changes without deprecation
- **Exception**: If the removed parameters were already marked `:deprecated => true`
  in the base branch (check the previous apipie declarations or `permitted_params`),
  then removal is the expected final step of the deprecation cycle — not a breaking
  change. Mark as PASS in that case.

### 3.9 Performance patterns
**Run when:** changed files include `.rb` files under `app/` or `lib/`.

Look for common performance issues in the diff:
- N+1 queries: `.each` blocks calling associations without `.includes`
- Unbounded queries: `.all` or `.where(...)` without `.limit` in controllers
- `.to_a` on large ActiveRecord relations
- Missing database indexes for new foreign keys in migrations
- Large string allocations in loops

Only flag patterns with clear evidence, not hypothetical concerns.

### 3.10 API counterparts for new controllers
**Run when:** changed files include new files under `app/controllers/` (not `api/`).

If a new controller is added under `app/controllers/` (not `api/`):
- Check whether a matching `app/controllers/api/v2/` controller exists
- This is a reminder, not a hard requirement — note it if missing

## Step 4: Human-Only Reminders

At the end of the report, list these items that require human follow-up:
- [ ] Does the new functionality have a Hammer CLI counterpart?
- [ ] Has necessary RPM/deb packaging been done?
- [ ] Who will provide user documentation?
- [ ] Who will provide a community demo (if applicable)?
- [ ] Are Upgrade Notes or New Features docs needed?

## Output Format

Structure the report as:

```
## Foreman PR Review: [commit title or branch name]

**Project type:** core | plugin | smart_proxy
**Commits reviewed:** [count]
**Base:** [branch]

### Convention Checks
[Pass/Warn/Fail per check]

### AI Assessment

#### [Check name] — [PASS | WARNING | ISSUE]
[Explanation with file:line references]

...

### Human Follow-up Required
- [ ] Hammer CLI counterpart
- [ ] Packaging
- [ ] User documentation
- [ ] Community demo
- [ ] Upgrade notes

### Summary
[1-2 sentence overall assessment: ready to merge, needs changes, or needs discussion]
```
