#!/usr/bin/env bash
# kickoff-assessments.sh — bulk-create one assessment issue per target and
# assign each to GitHub Copilot.
#
# Prerequisites:
#   - gh CLI authenticated with write access to the harness repo
#   - $HARNESS_REPO env var set to "<owner>/<harness-repo>"
#   - targets.txt next to this script's parent dir, one "owner/repo" per line
#     (lines starting with # are ignored, blank lines ignored)
#
# Usage:
#   HARNESS_REPO=your-org/code-assessment-harness ./kickoff-assessments.sh \
#       [path/to/targets.txt] [focus-areas-string]
#
# Output:
#   - kickoff.log appended with: <iso8601>\t<target>\t<issue#>\t<status>
#   - One issue per target in $HARNESS_REPO assigned to Copilot

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness_dir="$(cd "${script_dir}/.." && pwd)"

targets_file="${1:-${harness_dir}/targets.txt}"
focus_areas="${2:-Follow the standard rubric in assessment-standards.instructions.md.}"
log_file="${harness_dir}/kickoff.log"

: "${HARNESS_REPO:?HARNESS_REPO must be set, e.g. your-org/code-assessment-harness}"

if [[ ! -f "$targets_file" ]]; then
  echo "error: targets file not found: $targets_file" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found in PATH" >&2
  exit 1
fi

# Resolve Copilot's bot node ID once. suggestedActors is a Repository field
# (not a top-level Query field), and the loginNames arg is unreliable across
# schema versions, so we list all assignable actors on the harness repo and
# filter client-side via jq.
harness_owner="${HARNESS_REPO%%/*}"
harness_name="${HARNESS_REPO##*/}"

copilot_bot_id="$(
  gh api graphql \
    -F owner="$harness_owner" -F name="$harness_name" \
    -f query='
      query($owner: String!, $name: String!) {
        repository(owner: $owner, name: $name) {
          suggestedActors(capabilities: [CAN_BE_ASSIGNED], first: 50) {
            nodes { ... on Bot { id login } ... on User { id login } }
          }
        }
      }' \
    --jq '.data.repository.suggestedActors.nodes[] | select(.login=="copilot-swe-agent") | .id' \
    2>/dev/null || true
)"

if [[ -z "$copilot_bot_id" || "$copilot_bot_id" == "null" ]]; then
  echo "error: could not resolve Copilot bot id via suggestedActors." >&2
  echo "       Verify Copilot coding agent is enabled for $HARNESS_REPO." >&2
  echo "       (At repo Settings → Code & automation → Copilot, or org level.)" >&2
  exit 1
fi

echo "Copilot actor id: $copilot_bot_id"
echo "Harness repo:     $HARNESS_REPO"
echo "Targets file:     $targets_file"
echo "Log file:         $log_file"
echo

while IFS= read -r line || [[ -n "$line" ]]; do
  # skip blanks and comments
  [[ -z "${line// }" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue

  target="${line//[[:space:]]/}"
  if [[ "$target" != */* ]]; then
    echo "skip (malformed): $line" >&2
    continue
  fi

  owner="${target%%/*}"
  repo="${target##*/}"

  echo "→ $owner/$repo"

  prompt_body="$("${script_dir}/render-prompt.sh" "$owner" "$repo" "$focus_areas")"

  # Create the issue. We don't pass --assignee here because Copilot is a Bot
  # actor and gh's --assignee flag is restricted to users on some GH versions.
  issue_url="$(
    gh issue create \
      --repo "$HARNESS_REPO" \
      --title "assess: ${owner}/${repo}" \
      --body "$prompt_body" \
      2>/dev/null
  )"
  issue_number="${issue_url##*/}"

  # Resolve the issue's node id and assign Copilot via GraphQL.
  issue_node_id="$(
    gh api "repos/${HARNESS_REPO}/issues/${issue_number}" --jq '.node_id'
  )"

  gh api graphql \
    -H 'GraphQL-Features: issues_copilot_assignment_api_support' \
    -H 'GraphQL-Features: coding_agent_model_selection' \
    -f query='
      mutation($assignableId: ID!, $actorIds: [ID!]!) {
        replaceActorsForAssignable(input: {assignableId: $assignableId, actorIds: $actorIds}) {
          assignable { ... on Issue { number } }
        }
      }' \
    -f assignableId="$issue_node_id" \
    -f actorIds[]="$copilot_bot_id" \
    >/dev/null

  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\t%s\t%s\t%s\n' "$ts" "$target" "$issue_number" "assigned" >> "$log_file"
  echo "   issue #$issue_number created and assigned to Copilot"
done < "$targets_file"

echo
echo "Done. See $log_file"
