# Harness repo instructions for GitHub Copilot

This repository is an **assessment harness**. It exists to run the
`code-assessor` Cloud Agent against external target repos and collect the
resulting assessments here for human review.

## What lives here

- `.github/agents/code-assessor.agent.md` — the custom Cloud Agent that does
  the analysis.
- `.github/instructions/assessment-standards.instructions.md` — the rubric
  every assessment must follow.
- `analyses/<owner>__<repo>/assessment.md` — one assessment per target,
  written by the agent in its PR.
- Issues in this repo are the **work queue**: one issue per target, each
  assigned to `@copilot`.

## Rules for any Copilot work in this repo

1. **Never modify a target repo.** All work happens here. Target reads go
   through `github-mcp-server` using the `COPILOT_MCP_GITHUB_PAT` secret.
2. **One assessment per PR.** Each PR adds exactly one file under
   `analyses/<owner>__<repo>/assessment.md` and nothing else.
3. **Follow the assessment rubric** in
   `.github/instructions/assessment-standards.instructions.md` exactly.
4. **Close the triggering issue** via `Closes #N` in the PR body.
5. **Never store secrets or PII** in assessments — redact if encountered.

## How to run an assessment manually

1. Open an issue in this repo titled `assess: <owner>/<repo>`.
2. In the body, include the rendered prompt from
   `prompts/assess-repo.template.md` with `{{target_owner}}`,
   `{{target_repo}}`, and `{{focus_areas}}` substituted.
3. Assign the issue to `@copilot`.
4. Wait for the Copilot PR to appear, review it, then merge.

The `scripts/kickoff-assessments.sh` script automates steps 1–3 across a
list of targets in `targets.txt`.
