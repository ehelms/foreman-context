#!/bin/bash
# upstream-triage.sh
#
# Fetch and search upstream Foreman issues from Redmine (projects.theforeman.org).
# Used by the sat-upstream-triage Claude Code skill for data retrieval.
#
# Usage:
#   upstream-triage.sh fetch <issue_id>
#   upstream-triage.sh search <query> <project> [limit]
#   upstream-triage.sh list-open <project> [limit]
#
# Environment:
#   REDMINE_API_KEY       Required. Redmine API token.
#   FOREMAN_REDMINE_URL   Optional. Default: https://projects.theforeman.org
#
# Output:
#   JSON to stdout, errors to stderr.
#
# Prerequisites:
#   - curl and jq installed
#   - Redmine API key from projects.theforeman.org/my/account

set -euo pipefail

REDMINE_URL="${FOREMAN_REDMINE_URL:-https://projects.theforeman.org}"

if [[ -z "${REDMINE_API_KEY:-}" ]]; then
  echo "ERROR: REDMINE_API_KEY is not set." >&2
  echo "Get your API key from ${REDMINE_URL}/my/account" >&2
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 {fetch|search|list-open} [args...]" >&2
  echo "" >&2
  echo "Commands:" >&2
  echo "  fetch <issue_id>                   Fetch a single issue with journals" >&2
  echo "  search <query> <project> [limit]   Search issues by subject" >&2
  echo "  list-open <project> [limit]        List open issues" >&2
  exit 1
fi

curl_redmine() {
  local url="$1"
  local http_code body

  body=$(mktemp)
  trap 'rm -f "$body"' RETURN

  http_code=$(curl -s -o "$body" -w '%{http_code}' \
    -H "X-Redmine-API-Key: ${REDMINE_API_KEY}" \
    -H "Accept: application/json" \
    "$url" 2>/dev/null) || {
    echo "ERROR: curl failed. Check your network/VPN connection." >&2
    exit 2
  }

  if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    echo "ERROR: Authentication failed (HTTP $http_code)." >&2
    echo "Check your REDMINE_API_KEY." >&2
    exit 2
  fi

  if [[ "$http_code" == "404" ]]; then
    cat "$body"
    return 1
  fi

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Redmine API returned HTTP $http_code" >&2
    cat "$body" >&2
    exit 3
  fi

  cat "$body"
}

format_issue() {
  local base_url="$REDMINE_URL"
  jq --arg base_url "$base_url" '{
    id: .issue.id,
    subject: .issue.subject,
    description: .issue.description,
    tracker: .issue.tracker.name,
    status: .issue.status.name,
    priority: .issue.priority.name,
    category: (.issue.category.name // null),
    project: .issue.project.name,
    project_id: .issue.project.id,
    target_version: (.issue.fixed_version.name // null),
    author: .issue.author.name,
    assigned_to: (.issue.assigned_to.name // null),
    created_on: .issue.created_on,
    updated_on: .issue.updated_on,
    closed_on: (.issue.closed_on // null),
    url: "\($base_url)/issues/\(.issue.id)",
    custom_fields: ([.issue.custom_fields[]? | {(.name): .value}] | add // {}),
    journals: [.issue.journals[]? | {
      id: .id,
      user: .user.name,
      created_on: .created_on,
      notes: (.notes // "")
    }],
    related_issues: [.issue.relations[]? | {
      id: .id,
      issue_id: .issue_id,
      issue_to_id: .issue_to_id,
      relation_type: .relation_type
    }]
  }'
}

format_issue_list() {
  local base_url="$REDMINE_URL"
  jq --arg base_url "$base_url" '[.issues[]? | {
    id: .id,
    subject: .subject,
    description: .description,
    tracker: .tracker.name,
    status: .status.name,
    priority: .priority.name,
    category: (.category.name // null),
    project: .project.name,
    author: .author.name,
    assigned_to: (.assigned_to.name // null),
    created_on: .created_on,
    updated_on: .updated_on,
    url: "\($base_url)/issues/\(.id)"
  }]'
}

CMD="$1"
shift

case "$CMD" in
  fetch)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 fetch <issue_id>" >&2
      exit 1
    fi
    ISSUE_ID="$1"
    data=$(curl_redmine "${REDMINE_URL}/issues/${ISSUE_ID}.json?include=journals,relations") || {
      jq -n --arg id "$ISSUE_ID" '{error: "Issue not found", issue_id: $id}'
      exit 0
    }
    echo "$data" | format_issue
    ;;

  search)
    if [[ $# -lt 2 ]]; then
      echo "Usage: $0 search <query> <project> [limit]" >&2
      exit 1
    fi
    QUERY="$1"
    PROJECT="$2"
    LIMIT="${3:-5}"
    ENCODED_QUERY=$(printf '%s' "$QUERY" | jq -sRr @uri)
    data=$(curl_redmine "${REDMINE_URL}/issues.json?project_id=${PROJECT}&subject=~${ENCODED_QUERY}&status_id=*&limit=${LIMIT}&sort=updated_on:desc") || {
      echo "[]"
      exit 0
    }
    echo "$data" | format_issue_list
    ;;

  list-open)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 list-open <project> [limit]" >&2
      exit 1
    fi
    PROJECT="$1"
    LIMIT="${2:-20}"
    data=$(curl_redmine "${REDMINE_URL}/issues.json?project_id=${PROJECT}&status_id=open&sort=created_on:desc&limit=${LIMIT}") || {
      echo "[]"
      exit 0
    }
    echo "$data" | format_issue_list
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: $0 {fetch|search|list-open} [args...]" >&2
    exit 1
    ;;
esac
