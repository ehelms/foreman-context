---
name: foreman-upstream-triage
description: Triage upstream Foreman community issues on projects.theforeman.org (Redmine). Validates completeness, detects duplicates, classifies (actionable, abandoned, duplicate, incomplete, stale, resolved), and maps to downstream Satellite Jira.
parameters:
  - name: issue_identifier
    description: |
      Redmine issue number or URL. Examples:
        /foreman-upstream-triage 12345
        /foreman-upstream-triage https://projects.theforeman.org/issues/12345
    required: false
  - name: mode
    description: |
      "single" for one issue (default), "batch" for processing multiple open issues.
      Examples:
        /foreman-upstream-triage batch
        /foreman-upstream-triage 12345
    required: false
---

# Upstream Foreman Issue Triage (Redmine)

Triage upstream Foreman community issues on projects.theforeman.org (Redmine) against community contribution guidelines. Validates completeness, detects duplicates, classifies the issue, and optionally maps to downstream Satellite Jira issues.

This skill targets the **upstream Foreman Redmine tracker**.

Read `references/foreman-issue-guidelines.md` before running validation.

## Prerequisites

- `REDMINE_API_KEY` env var set (get from https://projects.theforeman.org/my/account)
- `curl` and `jq` installed
- Optional: `FOREMAN_REDMINE_URL` env var if using a different Redmine instance
- Optional: Jira MCP (Rovo) for downstream mapping

The script `upstream-triage.sh` is in `$(dirname {SCRIPT_PATH})/`.

## Step 1: Parse Input and Fetch Issue

Extract the issue ID from `{{ issue_identifier }}`:
- URL format: `https://projects.theforeman.org/issues/12345` → `12345`
- Number format: Use directly

If `{{ mode }}` is "batch", skip to the Batch Mode section below.

Fetch the issue:

```bash
$(dirname {SCRIPT_PATH})/upstream-triage.sh fetch {ISSUE_ID}
```

If the connection fails (Anubis anti-bot, VPN, missing API key), inform the user. Offer to proceed with a manually-pasted issue description — ask the user to provide the issue subject, description, tracker type, status, and dates, then work from that text directly.

## Step 2: Validate Issue Completeness

Using the fetched issue JSON and the Foreman guidelines in `references/foreman-issue-guidelines.md`, evaluate each of these checks:

| Check | What to verify | OK when |
|-------|---------------|---------|
| Subject | Descriptive title | 3+ words, not generic ("bug", "error", "problem" alone) |
| Tracker | Issue type set | Bug, Feature, or Refactor |
| Category | Component assigned | Category field is not null |
| Version | Foreman/Katello version in description | Pattern like `Foreman X.Y`, `Katello X.Y`, or version number in context |
| OS | Operating system in description | Pattern like `RHEL`, `CentOS`, `Debian`, `Ubuntu`, or specific version |
| Steps to reproduce | Reproduction steps present | Markers like "steps", "to reproduce", "how to", numbered list describing actions |
| Expected vs actual | Both behaviors described | Keywords like "expected", "actual", "should", "instead", "but" indicating both states |
| Logs/errors | Error output included | Code blocks, stack traces, log snippets, or error messages |
| Staleness | Last activity date | Warning if no activity in 12+ months |

Present results as a table with `[OK]`, `[WARNING]`, or `[MISSING]` tags for each check.

**GATE**: Ask the user whether to proceed to duplicate detection, or stop and request more information from the reporter first.

## Step 3: Detect Duplicates

Extract 5-10 search keywords from the issue — focus on specific nouns, error messages, component names, and distinctive phrases.

Search for candidates using progressive queries:

```bash
$(dirname {SCRIPT_PATH})/upstream-triage.sh search "{keywords}" foreman 5
```

If the first search returns few results, try shorter keyword combinations.

For each candidate returned, assess whether it describes the **same root problem** (not just similar symptoms). Consider:
- Do the subjects describe the same issue?
- Are the affected components/areas the same?
- Do the descriptions match in what's broken and how?
- Is the candidate closed (fix may already exist)?

Present candidates with your assessment of similarity.

**GATE**: Ask the user to confirm which candidates (if any) are genuine duplicates.

## Step 4: Classify Issue

Based on the validation results, duplicate candidates, and issue content, classify the issue into exactly ONE category, evaluated in this priority order:

| Priority | Category | Criteria | Typical Action |
|----------|----------|----------|----------------|
| 1 | **Duplicate** | Strong duplicate match confirmed by user in Step 3 | Close with reference to canonical issue |
| 2 | **Abandoned** | Last activity over 12 months ago, no linked PRs or recent interest | Comment inviting reporter to confirm; close after 30-day grace |
| 3 | **Stale but valid** | 6-12 months inactive but the problem is still relevant | Tag for review |
| 4 | **Incomplete** | Multiple critical checks fail (no version, no steps, no expected behavior) | Comment listing exactly what info is missing |
| 5 | **Resolved by time** | Filed against EOL version, area has changed significantly | Close with note that fix exists in current versions |
| 6 | **Actionable** | Sufficient information, describes a real current problem | Keep open, ensure correct categorization |

Rules:
- When uncertain between Actionable and another category, prefer **Actionable** (conservative default)
- Only classify as Duplicate when the **root cause** is the same, not just similar symptoms
- For Abandoned issues, check if there are linked PRs or recent references before classifying

Present: classification, confidence (high/medium/low), reasoning, and recommended action.

**GATE**: Ask the user to confirm the classification before any actions.

## Step 5: Map to Downstream Jira (Optional)

Scan the issue JSON for downstream Satellite Jira references:

1. **Custom fields**: Check "Red Hat JIRA", "JIRA", or "Downstream" custom fields for SAT-\d+ keys or Jira URLs
2. **Issue text**: Scan description and journal notes for `SAT-\d+` patterns or `https://issues.redhat.com/browse/SAT-\d+` URLs
3. **Jira MCP search** (if available): Use Rovo MCP to search for related SAT issues by keywords

Present any matches found. This is **read-only** — never modify Jira.

## Step 6: Apply Actions (with Human Confirmation)

Based on the confirmed classification, present recommended actions:

- **Actionable**: No state change needed. Ensure category and priority are correct.
- **Incomplete**: Draft a polite comment listing missing information with a template to fill in.
- **Duplicate**: Draft a comment referencing the canonical issue. Recommend closing as duplicate.
- **Abandoned**: Draft a comment inviting the reporter to confirm if the issue persists. Note the 30-day grace period.
- **Stale but valid**: Draft a note for the relevant team to review.
- **Resolved by time**: Draft a comment noting the fix exists in current versions. Recommend closing.

All comments MUST start with: **"This assessment was generated by an AI-assisted triage tool."**

**GATE**: Get explicit user approval before posting any comments or changing any issue state. Comments and state changes are the user's responsibility — present drafts, do not post automatically.

## Batch Mode

When `{{ mode }}` is "batch":

```bash
$(dirname {SCRIPT_PATH})/upstream-triage.sh list-open foreman 20
```

For each issue returned, run Step 2 (validation) and present a summary table:

```
## Batch Validation Summary

| # | Issue | Subject | Status | Last Updated | Validation |
|---|-------|---------|--------|-------------|------------|
| 1 | #12345 | Title... | New | 2024-01-15 | [INCOMPLETE] |
| 2 | #12346 | Title... | Assigned | 2026-07-01 | [OK] |
```

Tag each issue: `[OK]` (passes checks), `[NEEDS REVIEW]` (2+ warnings), `[INCOMPLETE]` (missing critical info).

**GATE**: Ask the user which issues to proceed with for full triage (Steps 3-6).

## Common Mistakes

- Do not close issues without explicit user confirmation
- Do not modify downstream Jira — the mapper is read-only
- Always include AI disclosure in drafted comments
- Do not classify as Duplicate based on similar symptoms alone — the root cause must be the same
- Be conservative: when uncertain, classify as Actionable
