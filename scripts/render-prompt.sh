#!/usr/bin/env bash
# render-prompt.sh — substitute target placeholders in the prompt template.
#
# Usage:
#   render-prompt.sh <owner> <repo> [focus_areas]
#
# Writes the rendered prompt to stdout. The {{focus_areas}} placeholder
# defaults to "Follow the standard rubric in assessment-standards.instructions.md."

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <owner> <repo> [focus_areas]" >&2
  exit 2
fi

owner="$1"
repo="$2"
focus_areas="${3:-Follow the standard rubric in assessment-standards.instructions.md.}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
template="${script_dir}/../prompts/assess-repo.template.md"

if [[ ! -f "$template" ]]; then
  echo "error: template not found at $template" >&2
  exit 1
fi

awk \
  -v owner="$owner" \
  -v repo="$repo" \
  -v focus="$focus_areas" \
  '{
    gsub(/\{\{target_owner\}\}/, owner)
    gsub(/\{\{target_repo\}\}/, repo)
    gsub(/\{\{focus_areas\}\}/, focus)
    print
  }' "$template"
