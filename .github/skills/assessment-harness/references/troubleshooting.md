# Assessment Harness Troubleshooting

Detailed runbook for common operator failure modes. Loaded on demand by the
`assessment-harness` skill.

## Where to find logs

| What | Where |
|------|-------|
| Kickoff audit (issues created, Copilot assigned) | `kickoff.log` at harness root |
| Cloud Agent session transcript | Issue page in harness repo → "View session" link Copilot adds as a comment |
| MCP server tool calls | Inside the session transcript, expandable per turn |
| GitHub API errors | Session transcript + `gh api rate_limit` for global state |

## Symptom: No PR appeared after >30 min

Likely causes, in order of frequency:

1. **Cloud Agent session never started.** Check the issue page for a
   Copilot avatar comment. If absent:
   - Re-verify Copilot Cloud Agent is enabled in repo settings.
   - Re-run the `suggestedActors` query from Task 1 step 3.
   - Check `kickoff.log` for `assigned` status on this target — if the
     line is missing, the kickoff script failed silently.

2. **Session started but is stuck.** Open the session transcript. Look for:
   - Repeated MCP tool errors (rate limit, 403, 404).
   - The agent oscillating between the same tool calls — indicates the
     target is too large or the agent is confused.
   - Manually comment on the issue asking the agent to wrap up and
     submit what it has.

3. **PR was opened but auto-closed.** Filter PRs by `head:copilot/` and
   state `closed` — the agent may have abandoned a draft. Re-trigger by
   commenting on the issue.

## Symptom: PR opened but assessment is stub/empty or marked "context exhausted"

The target repo is too large for a single session.

Mitigations, in order:

1. **Narrow focus areas.** Pass a tight `focus-areas-string` to
   `kickoff-assessments.sh` so the agent samples less:

   ```bash
   HARNESS_REPO=... ./scripts/kickoff-assessments.sh targets.txt \
       "Focus only on top-level architecture, manifests, and CI config. Skip src/."
   ```

2. **Chunk by directory.** File multiple issues per target, each scoped to
   one subtree, e.g. `assess: bigorg/monorepo (services/billing only)`.
   Edit the issue body to tell the agent which subdirectory to traverse.

3. **Skip vendored code.** Add explicit "Skip `vendor/`, `node_modules/`,
   `dist/`, `build/`, `__generated__/`" to focus areas.

4. **Accept partial coverage.** If the target genuinely is too large, the
   `Coverage gaps` section in the assessment is the honest record. That's
   a feature, not a bug — log it and move on.

## Symptom: MCP error 404 or 403 on the target

| Error | Cause | Fix |
|-------|-------|-----|
| `404 Not Found` on `get_repository` | Target doesn't exist or PAT can't see it | Verify target spelling; confirm PAT resource owner includes the target's org |
| `403 Forbidden` with "Resource not accessible" | PAT scope missing | Add `Contents: Read`, `Metadata: Read`, `Pull requests: Read`, `Issues: Read` |
| `403` on private target | Fine-grained PAT not authorized for that org | Reissue PAT with that org as resource owner; some orgs require admin approval |
| `403` on archived target | Archived repos block some endpoints | Document in assessment and continue |

After updating the PAT, you must update the secret in
**Settings → Secrets and variables → Copilot** (NOT Actions), then re-trigger
the assessment by re-assigning Copilot to the issue.

## Symptom: MCP error "API rate limit exceeded"

Cloud Agent uses the PAT installed as `COPILOT_MCP_GITHUB_PAT` for all MCP
calls. Limits:

- Fine-grained PAT: **5,000 requests/hour** per token.
- GitHub App installation token: **5,000 requests/hour per repository
  installation**, scaling with the number of installed repos. For >50
  targets, prefer a GitHub App.
- Secondary rate limits: bursty traffic to a single repo can trip these
  even under the primary limit.

Mitigations:

1. **Throttle kickoffs.** Run batches of ~25–50 targets, then wait 1 hour.
   The kickoff script does not auto-throttle.
2. **Switch to a GitHub App.** Install on each target org; the harness
   gets a per-installation token via the app's auth flow. Higher cumulative
   limit and better audit trail.
3. **Check current state:**

   ```bash
   gh api rate_limit --jq '.rate'
   ```

4. **Spread across multiple PATs/Apps.** Multiple harness repos each with
   their own credential, partitioned by target org.

## Symptom: Assessment cites the wrong target

The agent parses `target_owner` and `target_repo` from the triggering issue
body. If the body is missing, malformed, or contains multiple targets, the
agent may pick wrong.

Fix:

1. Open the issue and check the body matches the rendered template.
2. If missing, run `scripts/render-prompt.sh <owner> <repo>` and paste the
   output as a new issue body.
3. The agent's hard rules say "if the issue mentions multiple targets,
   stop and ask for one issue per target" — if you see this comment,
   close the issue and re-file.

## Symptom: Copilot wasn't assigned to the issue

Check `kickoff.log` for the target. If the `assigned` status is missing or
the script errored, the `replaceActorsForAssignable` mutation failed. Common
causes:

1. **Stale Copilot bot id.** The script resolves the id per run via
   `suggestedActors`. If that returned `null`, the script exits before
   creating issues. If it returned a stale id, mutation will 404.
   Re-run the script.

2. **Missing GraphQL feature headers.** The mutation requires both:

   ```
   GraphQL-Features: issues_copilot_assignment_api_support
   GraphQL-Features: coding_agent_model_selection
   ```

   The kickoff script passes both as separate `-H` flags. If you've forked
   the script, verify both headers are still present (they were both
   required as of the last verified GitHub API behavior).

3. **Permissions.** The `gh` CLI auth must have `repo` (or fine-grained
   `Issues: Write`) on the harness repo. Check with `gh auth status`.

4. **Manual fallback.** Assign via the web UI: open issue → Assignees →
   pick "Copilot". This works from any browser session with
   appropriate access.

## PAT rotation procedure

Rotate quarterly or immediately on suspected compromise.

1. Generate a new fine-grained PAT or GitHub App installation token with
   read-only scope on the same target orgs.
2. Update `COPILOT_MCP_GITHUB_PAT` in the harness repo's
   **Copilot secrets** (not Actions secrets).
3. Re-trigger one assessment as a smoke test (re-assign Copilot to a
   previously-completed issue, or kick off a single new target).
4. Verify the session transcript shows successful MCP reads with the new
   credential.
5. Revoke the old PAT.

## Incident: A write appeared on a target repo

This should be **impossible** given the agent's hard rules and a read-only
PAT, but if it happens:

1. **Immediately rotate `COPILOT_MCP_GITHUB_PAT`.**
2. Audit `.github/agents/code-assessor.agent.md` for tampering.
3. Pull the offending session transcript and the GitHub audit log for the
   target repo to identify which tool call wrote.
4. File a Copilot product issue with GitHub support including the session
   id and the offending tool call.
5. Notify the target repo owner.
6. Treat as P0 — the read-only guarantee is the entire compliance story
   for this offering.

## Verifying the rubric is followed

Reviewers should reject PRs that miss any of:

- All 10 rubric sections in order.
- `Evidence` section with at least one citation per claim that has a
  risk rating.
- `Coverage gaps` section present (even if "None").
- No marketing language; direct prose only.
- File paths in backticks.

The rubric source of truth is
`.github/instructions/assessment-standards.instructions.md`.
