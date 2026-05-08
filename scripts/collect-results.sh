#!/usr/bin/env bash
# collect-results.sh — pull every assessment.md the Copilot agent has
# written into the harness via PRs and save them locally under results/.
#
# Prerequisites:
#   - gh CLI authenticated with read access to $HARNESS_REPO
#   - $HARNESS_REPO env var set to "<owner>/<harness-repo>"
#
# Usage:
#   HARNESS_REPO=your-org/code-assessment-harness ./collect-results.sh [pr-state]
#
# pr-state defaults to "all" (open + merged + closed). Use "merged" to only
# collect human-reviewed-and-approved assessments.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness_dir="$(cd "${script_dir}/.." && pwd)"
results_dir="${harness_dir}/results"

pr_state="${1:-all}"

: "${HARNESS_REPO:?HARNESS_REPO must be set, e.g. your-org/code-assessment-harness}"

mkdir -p "$results_dir"

# List PRs authored by Copilot that touch analyses/.
# We use --search rather than --author because the bot login varies per host.
mapfile -t pr_numbers < <(
  gh pr list \
    --repo "$HARNESS_REPO" \
    --state "$pr_state" \
    --search 'in:title "assess:" head:copilot/' \
    --json number \
    --jq '.[].number'
)

if [[ ${#pr_numbers[@]} -eq 0 ]]; then
  echo "No assessment PRs found in $HARNESS_REPO (state=$pr_state)."
  exit 0
fi

echo "Collecting ${#pr_numbers[@]} assessment PR(s) from $HARNESS_REPO into $results_dir"

for pr in "${pr_numbers[@]}"; do
  # Find the assessment.md file path in the PR.
  files_json="$(gh pr view "$pr" --repo "$HARNESS_REPO" --json files,title,state,mergedAt,url)"

  path="$(
    printf '%s' "$files_json" \
      | awk 'BEGIN{RS="\""} /^analyses\// { print; exit }'
  )"

  if [[ -z "$path" ]]; then
    echo "PR #$pr: no analyses/**/*.md file found, skipping"
    continue
  fi

  # path looks like analyses/<owner>__<repo>/assessment.md
  rel="${path#analyses/}"        # <owner>__<repo>/assessment.md
  target_dir="${rel%/*}"         # <owner>__<repo>

  out_dir="${results_dir}/${target_dir}"
  mkdir -p "$out_dir"

  out_file="${out_dir}/pr-${pr}.md"

  # Get the file content from the PR's head ref
  head_ref="$(gh pr view "$pr" --repo "$HARNESS_REPO" --json headRefName --jq '.headRefName')"

  if gh api "repos/${HARNESS_REPO}/contents/${path}?ref=${head_ref}" \
       --jq '.content' 2>/dev/null \
     | base64 -d > "$out_file" 2>/dev/null; then
    echo "PR #$pr → $out_file"
  else
    echo "PR #$pr: failed to fetch $path on $head_ref" >&2
  fi
done

echo
echo "Done. Results in $results_dir"
