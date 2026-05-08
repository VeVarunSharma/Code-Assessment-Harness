#!/usr/bin/env bash
#
# extract-sections.sh — validate an assessment.md against the rubric.
#
# Usage:
#   extract-sections.sh <rubric-path> <assessment-path>
#
# Reads the rubric file (assessment-standards.instructions.md) and parses
# every "### N. `<heading>`" line under "## Required sections (in order)" to
# build the canonical list of expected headings (1 H1 plus 9 H2s = 10 total).
# Then reads the assessment file and lists every "# " or "## " heading.
# Compares the two and emits a JSON report on stdout:
#
#   {
#     "expected": [...],   # ordered list of canonical heading strings
#     "found":    [...],   # ordered list of headings actually present
#     "missing":  [...],   # canonical headings that are absent
#     "empty":    [...],   # found headings whose section body is empty
#     "ok":       true|false
#   }
#
# The H1 entry is normalised: the rubric template
# `# Assessment: {target_owner}/{target_repo}` is matched against any
# `# Assessment: <slug>` heading in the assessment.
#
# Exit code is always 0 — the workflow decides pass/fail by reading "ok".
# Stderr carries human-readable progress noise; stdout is JSON only.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <rubric-path> <assessment-path>" >&2
  exit 2
fi

rubric_path="$1"
assessment_path="$2"

if [[ ! -f "$rubric_path" ]]; then
  echo "rubric not found: $rubric_path" >&2
  exit 2
fi
if [[ ! -f "$assessment_path" ]]; then
  echo "assessment not found: $assessment_path" >&2
  exit 2
fi

mapfile_compat() {
  # Portable replacement for `mapfile -t <array> < <(cmd)`.
  # Usage: mapfile_compat ARRNAME < <(cmd)
  # Bash 3 (macOS default) has no mapfile builtin.
  local _arr_name="$1"
  local _line
  eval "$_arr_name=()"
  while IFS= read -r _line; do
    eval "$_arr_name+=(\"\$_line\")"
  done
}

# ----- 1. Parse rubric → canonical expected headings -----
#
# The rubric uses lines like:
#     ### 1. `# Assessment: {target_owner}/{target_repo}`
#     ### 2. `## Summary`
#     ...
#     ### 10. `## Evidence`
# We extract whatever is inside the backticks and keep their order.

mapfile_compat expected < <(
  awk '
    /^## Required sections \(in order\)/ { in_section=1; next }
    /^## Style rules/                    { in_section=0 }
    in_section && /^### [0-9]+\. `[^`]+`/ {
      # Strip "### N. `" prefix and trailing backtick
      sub(/^### [0-9]+\. `/, "", $0)
      sub(/`.*$/, "", $0)
      print $0
    }
  ' "$rubric_path"
)

if [[ ${#expected[@]} -eq 0 ]]; then
  echo "could not parse expected sections from rubric" >&2
  exit 2
fi

# ----- 2. Parse assessment → found headings -----
#
# We only care about H1 (`# `) and H2 (`## `) — the rubric never uses H3+
# for canonical sections. Trim trailing whitespace.

mapfile_compat found < <(
  awk '
    /^# [^#]/   { sub(/[[:space:]]+$/, "", $0); print $0; next }
    /^## [^#]/  { sub(/[[:space:]]+$/, "", $0); print $0 }
  ' "$assessment_path"
)

# ----- 3. Compute missing -----
#
# For each expected heading, check that the assessment contains a heading
# matching it. The H1 is treated specially: rubric template
# `# Assessment: {target_owner}/{target_repo}` matches any `# Assessment: ...`.

missing=()
for expected_heading in "${expected[@]}"; do
  if [[ "$expected_heading" == "# Assessment: "* ]]; then
    if ! printf '%s\n' "${found[@]}" | grep -q '^# Assessment: '; then
      missing+=("$expected_heading")
    fi
  else
    if ! printf '%s\n' "${found[@]}" | grep -Fxq "$expected_heading"; then
      missing+=("$expected_heading")
    fi
  fi
done

# ----- 4. Compute empty (H2 sections present but with no body lines) -----
#
# A section is "empty" if there is no non-blank, non-heading line between
# its heading and the next heading (or EOF). We only check H2 sections —
# the H1 (`# Assessment: ...`) is intentionally body-less by rubric design.

empty=()
for heading in "${found[@]}"; do
  case "$heading" in
    "# "*) continue ;;  # skip H1 — body-less by design
  esac
  body=$(awk -v h="$heading" '
    BEGIN { in_section=0 }
    {
      if ($0 == h) { in_section=1; next }
      if (in_section && /^#{1,6} /) { exit }
      if (in_section && NF > 0)     { print }
    }
  ' "$assessment_path")
  if [[ -z "$body" ]]; then
    empty+=("$heading")
  fi
done

# ----- 5. Compute out_of_order -----
#
# Walk the canonical expected list and the found headings in parallel.
# An expected heading is "out of order" if it appears in `found` AFTER a
# heading that should come later in the canonical sequence.
#
# Algorithm: for each expected heading present in `found`, record its index
# in `found`. The recorded indices must be strictly increasing in the
# expected order — any decrease means the heading is misplaced.

out_of_order=()
prev_idx=-1
for expected_heading in "${expected[@]}"; do
  this_idx=-1
  found_idx=0
  for found_heading in "${found[@]}"; do
    if [[ "$expected_heading" == "# Assessment: "* ]]; then
      case "$found_heading" in
        "# Assessment: "*) this_idx=$found_idx; break ;;
      esac
    else
      if [[ "$found_heading" == "$expected_heading" ]]; then
        this_idx=$found_idx
        break
      fi
    fi
    found_idx=$((found_idx + 1))
  done
  if [[ $this_idx -ne -1 ]]; then
    if [[ $this_idx -lt $prev_idx ]]; then
      out_of_order+=("$expected_heading")
    fi
    prev_idx=$this_idx
  fi
done

# ----- 6. Emit JSON -----
#
# Use jq to safely escape strings. The "ok" field is true only when every
# canonical section is present, non-empty, and in the rubric's prescribed
# order, and the rubric itself parsed to exactly 10 sections.

ok="true"
expected_count=${#expected[@]}
if [[ $expected_count -ne 10 ]]; then
  ok="false"
fi
if [[ ${#missing[@]} -gt 0 || ${#empty[@]} -gt 0 || ${#out_of_order[@]} -gt 0 ]]; then
  ok="false"
fi

jq -n \
  --argjson expected     "$(printf '%s\n' "${expected[@]}" | jq -R . | jq -s .)" \
  --argjson found        "$(printf '%s\n' "${found[@]}"    | jq -R . | jq -s .)" \
  --argjson missing      "$(if [[ ${#missing[@]}      -eq 0 ]]; then echo '[]'; else printf '%s\n' "${missing[@]}"      | jq -R . | jq -s .; fi)" \
  --argjson empty        "$(if [[ ${#empty[@]}        -eq 0 ]]; then echo '[]'; else printf '%s\n' "${empty[@]}"        | jq -R . | jq -s .; fi)" \
  --argjson out_of_order "$(if [[ ${#out_of_order[@]} -eq 0 ]]; then echo '[]'; else printf '%s\n' "${out_of_order[@]}" | jq -R . | jq -s .; fi)" \
  --argjson expected_count "$expected_count" \
  --arg     ok       "$ok" \
  '{
    expected:$expected,
    found:$found,
    missing:$missing,
    empty:$empty,
    out_of_order:$out_of_order,
    expected_count:$expected_count,
    ok:($ok == "true")
  }'
