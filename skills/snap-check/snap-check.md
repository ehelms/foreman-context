# Snap Delivery Checker

Check whether upstream PRs linked to Jira issues in "Release Pending - Upstream" status have been delivered in a downstream snap. Compares git commit SHAs embedded in RPM names against PR merge commits using the GitHub compare API.

## Prerequisites

- **Settings file** — copy `.claude/commands/snap-check-settings.yaml.template` to `.claude/commands/snap-check-settings.yaml` and fill in your values:
  - `jira_api_token`: Create at https://id.atlassian.com/manage-profile/security/api-tokens using **"Create API token"** (NOT "Create API token with scopes" — scoped tokens lack transition permissions). Required for `--apply` mode.
  - `jira_email`: Your Atlassian account email
  - `ohsnap_url`: ohsnap base URL (default provided in template)
- **GitHub Issue field in Jira** — each Jira issue must have the upstream GitHub PR URL in the "GitHub Issue" field (`customfield_10747`). Without this, the skill cannot determine which PR to check.
- **VPN** — required for ohsnap API access
- **`gh` CLI** — authenticated (`gh auth login`) for GitHub compare API

## Arguments

`$ARGUMENTS`

Supported flags:
- `--apply` -- actually transition delivered Jira issues to "Testing" and post a comment. Without this flag, the skill runs in **report-only mode** (default).
- `--team <name>` -- filter Jira issues by Assigned Team field. Valid values: `proton`, `artemis`, `endeavour`, `rocket`, `jpl`. Appends `AND cf[10606] = sat-<name>` to the JQL. If omitted, queries all teams.
- `--snap <version>` -- snap version number (e.g., `183.0`). Fetches SRPM data from ohsnap API (requires VPN).
- `--jql "..."` -- override the default Jira query (must be quoted). When provided, `--team` is ignored.

If no `--snap` is provided and no inline JSON array is present, prompt the user to provide snap data.

Inline JSON input (starts with `[`): ohsnap changed packages data pasted directly as the argument, without the `--snap` flag.

## Configuration

- **Settings file**: `.claude/commands/snap-check-settings.yaml` (user-specific, not committed)
- **ohsnap API**: `{ohsnap_url}/api/releases/stream/snaps/{version}/rpms?all=true` (ohsnap_url from settings file)
- **Default JQL**: `project = SAT AND status = "Release Pending - Upstream" ORDER BY updated DESC` (appends `AND cf[10606] = sat-<team>` when `--team` is used)
- **Team field**: `cf[10606]` (Assigned Team). Values: `sat-proton`, `sat-artemis`, `sat-endeavour`, `sat-rocket`, `sat-jpl`
- **Jira cloud ID**: `https://redhat.atlassian.net`
- **Jira transition "Testing"**: transition id `101`
- **GitHub orgs to search**: `theforeman`, `Katello`

### RPM-to-Upstream-Repo Mapping

| RPM name pattern | Upstream GitHub repo |
|---|---|
| starts with `foreman-` (NOT `foreman-installer`, NOT `foreman-proxy`, NOT `foreman_rh_cloud`, NOT `foreman-selinux`, NOT other sub-packages) | `theforeman/foreman` |
| starts with `rubygem-katello-` | `Katello/katello` |
| starts with `rubygem-foreman_rh_cloud-` | `theforeman/foreman_rh_cloud` |
| starts with `foreman-installer-` | `theforeman/foreman-installer` |
| starts with `foreman-proxy-` | `theforeman/smart-proxy` |
| starts with `rubygem-hammer_cli-` (NOT `rubygem-hammer_cli_foreman`, NOT `rubygem-hammer_cli_katello`) | `theforeman/hammer-cli` |
| starts with `rubygem-hammer_cli_foreman-` (NOT `rubygem-hammer_cli_foreman_`) | `theforeman/hammer-cli-foreman` |
| starts with `rubygem-hammer_cli_katello-` | `Katello/hammer-cli-katello` |

## Execution Steps

### Step 0: Load Settings

Read `.claude/commands/snap-check-settings.yaml` using the Read tool. Parse the YAML content to extract:
- `jira_api_token`
- `jira_email`
- `ohsnap_url`

If the file doesn't exist, print an error telling the user to copy the template:
```
ERROR: Settings file not found.
Copy .claude/commands/snap-check-settings.yaml.template to .claude/commands/snap-check-settings.yaml
and fill in your values.
```
Then STOP.

Store these values for use in later steps. When constructing curl commands, substitute the actual values directly into the command string — do NOT use subshells like `$(grep ...)` to read the settings file at runtime, as this triggers permission prompts.

### Step 1: Parse Arguments

Check `$ARGUMENTS`:

1. Extract flags:
   - If `--apply` is present, set `apply_mode = true`. Otherwise `apply_mode = false`.
   - If `--team <name>` is present, extract the team name (e.g., `proton`). Validate it is one of: `proton`, `artemis`, `endeavour`, `rocket`, `jpl`. Append `AND cf[10606] = sat-<name>` to the default JQL.
   - If `--jql "..."` is present, extract the quoted JQL string and use it as the Jira query. This overrides `--team`.

2. Detect input:
   - If `--snap <version>` is present, extract the version number (e.g., `183.0`) and fetch from ohsnap.
   - If the remaining argument text starts with `[`: treat as inline JSON. Parse it as a JSON array of objects with structure `[{"repository": "...", "rhel": "...", "srpms": ["rpm1", "rpm2", ...]}]`.
   - If neither `--snap` nor inline JSON is provided: ask the user to provide snap data or use `--snap <version>`, then STOP.

### Step 2: Get Snap Package Data

**If snap version was provided**, fetch from ohsnap API:

```bash
curl -sk '{ohsnap_url}/api/releases/stream/snaps/{VERSION}/rpms?all=true'
```
Where `{ohsnap_url}` is from the settings file.

If curl fails or returns empty/non-JSON, report the error and STOP. The user likely needs VPN.

**If inline JSON was provided**, use it directly.

Store the result as `snap_data` (the JSON array).

### Step 3: Extract Git Commits from Target RPMs

From `snap_data`, collect ALL `srpms` entries across all repositories. Then for each RPM name, check if it matches a tracked package from the mapping table.

For each matched RPM, extract:
- **Git commit SHA**: regex `git([a-f0-9]{7,})` from the RPM name
- **Build timestamp**: regex `(\d{14})git` from the RPM name, format as `YYYY-MM-DD HH:MM:SS`
- **Version**: the version portion of the RPM NVR

If no git commit is embedded (stable releases like `rubygem-foreman_rh_cloud-14.1.2-1.el9sat`), record the version string and note that manual check may be needed.

Use a Bash + python3 pipeline to parse this. Print the extracted data as JSON:

```bash
echo 'SNAP_DATA_JSON' | python3 -c "
import json, re, sys

data = json.loads(sys.stdin.read())
mapping = {
    'rubygem-hammer_cli_katello-': 'Katello/hammer-cli-katello',
    'rubygem-hammer_cli_foreman-': 'theforeman/hammer-cli-foreman',
    'rubygem-hammer_cli-': 'theforeman/hammer-cli',
    'rubygem-katello-': 'Katello/katello',
    'rubygem-foreman_rh_cloud-': 'theforeman/foreman_rh_cloud',
    'foreman-installer-': 'theforeman/foreman-installer',
    'foreman-proxy-': 'theforeman/smart-proxy',
    'foreman-': 'theforeman/foreman',
}

foreman_subpkgs = ['foreman-installer','foreman_rh_cloud','foreman_maintain','foreman-selinux','foreman-dynflow','foreman-debug','foreman-cli','foreman-doc','foreman-libvirt','foreman-vmware','foreman-ec2','foreman-gce','foreman-openstack','foreman-ovirt','foreman-journald','foreman-service','foreman-telemetry','foreman-postgresql','foreman-redis','foreman-assets','foreman-pcp','foreman-proxy']
hammer_cli_subpkgs = ['rubygem-hammer_cli_foreman_','rubygem-hammer_cli_katello-']
results = {}
all_rpms = set()
for repo_data in data:
    for rpm in repo_data.get('rpms', repo_data.get('srpms', [])):
        all_rpms.add(rpm)

for rpm in all_rpms:
    for prefix, gh_repo in mapping.items():
        if prefix == 'foreman-' and any(x in rpm for x in foreman_subpkgs):
            continue
        if prefix == 'rubygem-hammer_cli-' and any(rpm.startswith(x) for x in hammer_cli_subpkgs):
            continue
        if prefix == 'rubygem-hammer_cli_foreman-' and 'rubygem-hammer_cli_foreman_' in rpm:
            continue
        if rpm.startswith(prefix):
            commit_match = re.search(r'git([a-f0-9]{7,})', rpm)
            ts_match = re.search(r'(\d{14})git', rpm)
            if gh_repo not in results or commit_match:
                results[gh_repo] = {
                    'rpm': rpm,
                    'commit': commit_match.group(1) if commit_match else None,
                    'build_ts': ts_match.group(1) if ts_match else None,
                }
            break

print(json.dumps(results, indent=2))
"
```

Record the output as `snap_rpms` -- a dict keyed by GitHub repo with commit and RPM info.

### Step 4: Query Jira for Issues

Fetch issues via the Jira REST API using credentials from settings:

```bash
curl -s -u "{jira_email}:{jira_api_token}" "https://redhat.atlassian.net/rest/api/3/search/jql" -G \
  --data-urlencode "jql={JQL_QUERY}" \
  --data-urlencode "maxResults=10" \
  --data-urlencode "fields=summary,status,assignee,components,customfield_10879"
```

Parse the `issues` array from the response. For each issue, note the value of `customfield_10879` (Preliminary Testing) — it can be `"Pass"`, `"Fail"`, or null. If empty, report "No issues in Release Pending - Upstream" and STOP.

### Step 5: Find Upstream PRs for Each Issue

For EACH Jira issue, try these methods in order to find the upstream PR. Stop at the first one that succeeds:

**Method 1 — Jira "GitHub Issue" field via REST API (primary)**
The Jira custom field `customfield_10747` stores the upstream GitHub PR/issue URL. Fetch it using the Jira API token and email from settings:

```bash
curl -s -u "{jira_email}:{jira_api_token}" "https://redhat.atlassian.net/rest/api/3/issue/{JIRA_KEY}?fields=customfield_10747"
```

Then parse the JSON response to extract `fields.customfield_10747`.

Run up to 5 of these in parallel (one per issue).

Parse the returned URL to extract `owner`, `repo`, and `number` from the pattern `github.com/{owner}/{repo}/pull/{number}` or `github.com/{owner}/{repo}/issues/{number}`.

If the URL points to a GitHub issue (not a PR), look for linked PRs in that issue. If the field is empty, fall through to Method 2.

**FailedQA edge case:** If `customfield_10879` (Preliminary Testing) = `"Fail"` for this issue, the PR in `customfield_10747` may be the old (failed) fix. The developer may have posted a newer PR URL in the Jira comments instead of updating the GitHub Issue field. In this case, after getting the PR from `customfield_10747`, also fetch the issue comments:

```bash
curl -s -u "{jira_email}:{jira_api_token}" "https://redhat.atlassian.net/rest/api/3/issue/{JIRA_KEY}/comment"
```

Scan all comment bodies for GitHub PR URLs matching `github.com/{owner}/{repo}/pull/{number}` in tracked repos. If a newer PR is found (posted after the `customfield_10747` PR was merged), use that PR instead. Report this in the output as "PR from comments (failedQA refix)".

**Method 2 — GitHub search by Jira key (fallback)**
Search GitHub for merged PRs referencing the Jira key via `gh` CLI:

```bash
gh search prs "{JIRA_KEY}" --owner=theforeman --owner=Katello --state=merged --json repository,number,mergedAt,mergeCommit,url --limit 5
```

Filter results to only PRs in tracked repos (theforeman/foreman, Katello/katello, theforeman/foreman_rh_cloud, theforeman/foreman-installer, theforeman/smart-proxy, theforeman/hammer-cli, theforeman/hammer-cli-foreman, Katello/hammer-cli-katello).

If neither method finds a PR, mark the issue as `no_pr_found`.

### Step 6: Check Commit Ancestry

For each (issue, PR, repo) combination where the snap has a matching RPM with an embedded git commit:

Run the GitHub compare API via Bash:

```bash
curl -s -H "Authorization: Bearer $(gh auth token)" \
  "https://api.github.com/repos/{OWNER}/{REPO}/compare/{SNAP_COMMIT}...{PR_MERGE_COMMIT}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps({'status': d['status'], 'ahead_by': d.get('ahead_by', 0), 'behind_by': d.get('behind_by', 0)}))"
```

Run up to 5 compare calls in parallel (multiple Bash tool calls in one message).

Interpret results:
- `status == "behind"` → the PR merge commit is BEHIND the snap commit → the snap contains the PR → **DELIVERED**
- `status == "identical"` → same commit → **DELIVERED**
- `status == "ahead"` → the PR merge commit is AHEAD of the snap → **NOT YET** (include `ahead_by` count in report)
- `status == "diverged"` → branches diverged → **MANUAL CHECK NEEDED**
- API error or missing data → **ERROR**

For RPMs without embedded git commits (stable releases), check if there's a version tag in the upstream repo. If not feasible, mark as **MANUAL CHECK NEEDED**.

### Step 7: Print Report

Output a formatted report to the console using emoji and box-drawing characters for visual clarity:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📦 Snap Delivery Check Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Mode:  🔍 REPORT ONLY (use --apply to transition)
  Team:  {team or "all"}
  Snap:  {snap_version or "inline data"}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Issues: {N}  │  ✅ Delivered: {M}  │  ⏳ Not yet: {X}  │  ⚪ No PR: {Y}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ DELIVERED
──────────────────
  🟢 SAT-XXXXX
  "{summary}"
  👤 {name}  │  🏷️  {components}
  🔗 {repo}#{number} (merged {date})
     {pr_html_url}
  📀 {srpm_name}
  ✅ Snap commit {snap_commit} contains PR commit {pr_commit}

⏳ NOT YET IN SNAP
──────────────────
  🔴 SAT-XXXXX
  "{summary}"
  👤 {name}  │  🏷️  {components}
  🔗 {repo}#{number} (merged {date})
     {pr_html_url}
  📀 {srpm_name}
  ⚠️  PR merge commit {pr_commit} is {N} commits AHEAD of snap commit {snap_commit}

🟡 MANUAL CHECK NEEDED
──────────────────
  🟡 SAT-XXXXX
  "{summary}"
  👤 {name}  │  🏷️  {components}
  📀 {srpm_name} (no embedded git commit)
  Reason: Stable release RPM — check version tag manually

🔄 FAILED QA — REFIX PR
──────────────────
  🔄 SAT-XXXXX
  "{summary}"
  👤 {name}  │  🏷️  {components}
  🔗 {repo}#{number} (merged {date}) — from comments (failedQA refix)
     {pr_html_url}
  📀 {srpm_name}
  ⚠️  Original PR {old_repo}#{old_number} was delivered but Preliminary Testing = Fail

⚪ NO UPSTREAM PR FOUND
──────────────────
  ⚪ SAT-XXXXX
  "{summary}"
  👤 {name}  │  🏷️  {components}
  No merged PR found in theforeman/Katello orgs referencing this issue

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Run with --apply to transition delivered issues.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Only include sections that have issues (skip empty sections).

### Step 8: Transition Issues (only with --apply)

If `apply_mode` is false, print "Run with --apply to transition delivered issues" and STOP.

If `apply_mode` is true, for each **DELIVERED** issue:

Transition to "Testing" via the Jira REST API using credentials from settings file:

```bash
curl -s -w "\nHTTP:%{http_code}" -X POST \
  -u "{jira_email}:{jira_api_token}" \
  -H "Content-Type: application/json" \
  -d '{"transition":{"id":"101"}}' \
  "https://redhat.atlassian.net/rest/api/3/issue/{JIRA_KEY}/transitions"
```

Where `{jira_email}` and `{jira_api_token}` are the values loaded from `snap-check-settings.yaml` in Step 0.

HTTP 204 = success. Run up to 5 transitions in parallel.

Print confirmation for each transitioned issue. If transition fails, report the error but continue with remaining issues.

## Error Handling

- **ohsnap curl failure**: Report error, suggest checking VPN, STOP.
- **No tracked RPMs found in snap data**: Report "No foreman/katello/foreman_rh_cloud packages found in snap data", STOP.
- **GitHub search rate limit**: Report which issues were checked before hitting the limit, note remaining issues.
- **GitHub compare API failure**: Mark the specific issue as ERROR, continue with others.
- **Jira query failure**: Report the error, STOP.
- **Jira transition failure**: Report the error for that issue, continue with remaining.
- **No issues found**: Report "No issues in Release Pending - Upstream status", STOP.
