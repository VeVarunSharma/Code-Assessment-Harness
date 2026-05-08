---
name: assessment-harness
description: Operator guide for the code-assessment harness. This skill should be used when working in the harness repo and the request involves setting up the harness, kicking off Copilot Cloud Agent assessments against external target repos, reviewing results, or troubleshooting issues with the assessment workflow. Triggers on phrases like "kick off assessments", "assess these repos", "run the assessor", "collect results", "Copilot didn't pick up the issue", "MCP can't reach target", "PAT scope", or "rate limited".
---

# Assessment Harness

## Overview

This skill guides the operator running the code-assessment harness. The
harness uses GitHub Copilot Cloud Agent to assess external target repos
**read-only** via the GitHub MCP server, writing each assessment as a PR back
to this harness repo for human review. The targets get zero footprint — no
issues, branches, PRs, or commits are created in them.

The actual assessment work is done by the `code-assessor` Cloud Agent defined
in `.github/agents/code-assessor.agent.md`. This skill is for the **operator**
driving the harness, not the agent itself.

## When to use this skill

- Setting up the harness repo for the first time.
- Adding new targets to assess.
- Kicking off a batch of assessments.
- Collecting, reviewing, or sharing assessment results.
- Diagnosing why an assessment failed, stalled, or produced incomplete output.
- Adjusting focus areas or rubric for a specific batch.

## Quick start (operator workflow)

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│  1. Setup    │──▶│  2. Targets  │──▶│  3. Kickoff  │──▶│  4. Collect  │
│  (one-time)  │   │  add lines   │   │  per batch   │   │  + review    │
└──────────────┘   └──────────────┘   └──────────────┘   └──────────────┘
```

## Task 1 — First-time harness setup

Run these once per harness repo. Verify each step before moving on.

1. **Confirm the harness repo has Copilot Cloud Agent enabled.**
   Settings → Code & automation → Copilot → Coding agent → must be ON.
   Requires Copilot Business or Enterprise. If absent, escalate to the org
   admin — there is no workaround.

2. **Set the cross-repo read PAT as a Copilot MCP secret.**
   Settings → Secrets and variables → **Copilot** (not Actions) →
   New repository secret → name: `COPILOT_MCP_GITHUB_PAT`.
   Token requirements:
   - Fine-grained PAT (or GitHub App installation token in production).
   - Scope: **read-only** on the target orgs/repos. `Contents: Read`,
     `Metadata: Read`, `Pull requests: Read`, `Issues: Read`. **No write
     scopes.**
   - If using a fine-grained PAT, set "Resource owner" to each target org
     and grant access to "All repositories" (or selected, if scoping
     tighter).

3. **Verify Copilot can be assigned to issues in the harness repo.**
   Run from the harness repo:

   ```bash
   gh api graphql -f query='
     query { suggestedActors(loginNames: ["copilot-swe-agent"], capabilities: [CAN_BE_ASSIGNED], first: 1) {
       nodes { ... on Bot { id login } ... on User { id login } }
     } }'
   ```

   Should return a non-null `id`. Empty result → Cloud Agent isn't enabled
   here (return to step 1).

4. **Confirm the agent definition loads.**
   Open the harness repo in Copilot CLI and ask:
   *"Show me the code-assessor agent."* If Copilot can't find it, the
   `.github/agents/code-assessor.agent.md` file isn't in the right place or
   custom agents aren't enabled for this org's Copilot tier (Pro+ minimum).

5. **Make scripts executable** (one-time per clone):

   ```bash
   chmod +x scripts/*.sh
   ```

## Task 2 — Add or update targets

Targets live in `targets.txt` at the harness root, one `owner/repo` per line.

```
# one owner/repo per line — comments and blank lines are ignored
octocat/Hello-World
# your-org/some-app
# your-org/another-service
```

To validate the file before kickoff:

```bash
grep -v '^#' targets.txt | grep -v '^$' | grep -v '/' && echo "BAD LINES ABOVE" || echo "OK"
```

Keep `targets.txt` out of git (it's in `.gitignore`). Use
`targets.example.txt` as a template.

## Task 3 — Kick off a batch of assessments

```bash
HARNESS_REPO=<owner>/<harness-repo> ./scripts/kickoff-assessments.sh \
    [path/to/targets.txt] [focus-areas-string]
```

What happens:
- For each target line, `kickoff-assessments.sh` renders the prompt template
  (`prompts/assess-repo.template.md`), creates an issue in the harness titled
  `assess: <owner>/<repo>`, and assigns it to Copilot via the
  `replaceActorsForAssignable` GraphQL mutation.
- Each assignment triggers a Cloud Agent session that runs against the
  harness, traverses the target via `github-mcp-server` reads, and opens a
  `copilot/...` PR adding `analyses/<owner>__<repo>/assessment.md`.
- Every kickoff is appended to `kickoff.log` for audit.

**Focus areas** is a free-text instruction the agent honors verbatim. Default
is to follow the standard rubric. Use focus areas to narrow scope — e.g.
`"Focus only on auth, secrets handling, and CI security scans."`

**Pacing for large batches.** Cloud Agent runs are concurrent per repo but
share API rate limit. For batches over ~50 targets, split `targets.txt` into
chunks of 25–50, run them an hour apart, and watch `gh api rate_limit`. See
`references/troubleshooting.md` for limits and mitigation.

## Task 4 — Review and collect results

1. **Review in PR UI.** Each assessment PR adds exactly one
   `analyses/<owner>__<repo>/assessment.md`. Reviewer checks:
   - All ten rubric sections present (per
     `.github/instructions/assessment-standards.instructions.md`).
   - `Coverage gaps` section is honest, not hand-wavy.
   - `Evidence` section has cited file paths with line ranges.
   - No secrets/PII leaked into the assessment.
   - Risk rating matches the cited evidence.

2. **Merge approved PRs.** Merging is the human "share with app team" gate.
   Unmerged PRs hold drafts/in-flight work.

3. **Pull results locally** for archiving or batch reporting:

   ```bash
   HARNESS_REPO=<owner>/<harness-repo> ./scripts/collect-results.sh merged
   ```

   Pass `merged` to only collect human-approved assessments. Default is
   `all` (open + merged + closed). Output goes to
   `results/<owner>__<repo>/pr-<num>.md`.

## Task 5 — Diagnose a failed or incomplete assessment

Quick triage tree:

| Symptom | First place to look |
|---------|---------------------|
| No PR appeared after >30 min | Cloud Agent session log on the issue |
| PR opened but assessment is stub/empty | Agent ran out of context — see chunking advice |
| `MCP error: 404` or `403` on target | PAT scope or org access |
| `MCP error: rate limit` | Throttle and stagger kickoffs |
| Assessment lists wrong target | Issue body missing/malformed prompt |
| Copilot wasn't assigned | `replaceActorsForAssignable` failed — see kickoff.log |

For the full playbook including exact log locations and fixes, load
`references/troubleshooting.md`.

## Hard constraints to remember

- The agent is forbidden from writing to target repos. If a reviewer ever
  sees a PR/issue/branch appear on a target, treat it as a **P0 incident** —
  rotate `COPILOT_MCP_GITHUB_PAT`, audit the agent definition, and review
  the agent's session log.
- The PAT must be read-only. If write scopes are present, the agent's hard
  rules are the only thing preventing target writes — that's fragile.
  Rotate to a read-only token.
- Never put real secrets, tokens, or customer PII in `targets.txt`,
  `kickoff.log`, or `results/**`. They are operator artifacts but may be
  shared with stakeholders.

## Resources

- `references/troubleshooting.md` — detailed runbook for the failure modes
  in Task 5, plus rate-limit math and PAT rotation procedure.
