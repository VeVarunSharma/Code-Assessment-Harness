# Code Assessment Harness

Self-contained harness for using GitHub Copilot Cloud Agents to assess
hundreds-to-thousands of source-code repositories **read-only**, with no
footprint on the target repos and human review of every result before sharing.

## Goals

In priority order:

1. **Live enterprise pilot.** The top goal is to validate this pattern
   against real repositories inside the operator's own enterprise — not
   just public OSS smoke-tests. Everything in this repo is built so a
   human operator can stand the harness up in their org, point it at
   their own production codebases, and get reviewable assessments back
   within hours.
2. **Zero footprint on target repos.** Targets are accessed read-only via
   the GitHub MCP server using a read-only PAT (or GitHub App
   installation token). No issues, branches, PRs, commits, agents, or
   instruction files are created in target repos — ever.
3. **Human review gate before any result leaves the harness.** Every
   assessment lands as a PR in the harness for explicit reviewer
   approval. Merging that PR is the deliberate "share with the app team"
   step. There is no auto-publish path.
4. **Scale to hundreds-to-thousands of repos.** A single batch script
   parameterises the prompt per target and assigns the Cloud Agent to
   each. Throughput is gated by GitHub API rate limits, not by the
   harness itself.
5. **Reusable across use cases.** The agent definition, rubric, and
   prompt template are all editable in this repo. The same harness
   pattern works for security audits, modernization scoping,
   architecture reviews, dependency inventories, and similar
   read-only-codebase analyses.

## Why this exists

GitHub Copilot Cloud Agent requires write access to whichever repo it runs in
— it always creates a `copilot/...` branch in an ephemeral GitHub Actions
environment scoped to that repo. That breaks the obvious "delegate per target
repo" approach when the constraint is read-only access to the targets and no
modifications (no issues, no branches, no PRs, no commits).

This harness inverts the model:

```
┌─────────────────┐       ┌──────────────────┐       ┌─────────────────┐
│ kickoff script  │──────▶│  HARNESS REPO    │──────▶│  TARGET REPOS   │
│ (gh CLI)        │       │  (write access)  │  read │  (read only via │
│                 │       │                  │  via  │   GH MCP/API)   │
│ creates issues  │       │  Cloud Agent     │  API  │                 │
│ assigns Copilot │       │  runs here, PRs  │       │  zero footprint │
│                 │       │  assessment.md   │       │                 │
└─────────────────┘       └──────────────────┘       └─────────────────┘
                                  │
                                  ▼
                          ┌──────────────────┐
                          │ collect script   │
                          │ pulls PR diffs   │
                          │ → results/       │
                          └──────────────────┘
```

The Cloud Agent runs against this **harness repo** (where it has the required
write access). It uses the GitHub MCP server, authenticated with a read-only
PAT, to traverse target repo content via the GitHub API — no clone, no fork,
no writes. The agent commits its output to a `copilot/...` branch in the
harness and opens a PR here. That PR is the human-review artifact; merging
it is the explicit "share with the app team" gate.

## Repository layout

```
assessment-harness/
├── README.md                                   # this file
├── .gitignore
├── targets.example.txt                         # one owner/repo per line
├── .github/
│   ├── agents/
│   │   └── code-assessor.agent.md              # The Cloud Agent
│   ├── instructions/
│   │   └── assessment-standards.instructions.md  # The rubric
│   ├── skills/
│   │   └── assessment-harness/                 # Operator skill (Copilot CLI)
│   │       ├── SKILL.md
│   │       └── references/troubleshooting.md
│   └── copilot-instructions.md                 # Repo-level rules
├── prompts/
│   └── assess-repo.template.md                 # Parameterized issue body
├── scripts/
│   ├── render-prompt.sh                        # Substitute {{target_*}} placeholders
│   ├── kickoff-assessments.sh                  # Bulk-create issues + assign Copilot
│   └── collect-results.sh                      # Pull assessment.md from each PR
└── results/                                    # Collected output (gitignored)
```

`.github/` only has special meaning at the **repo root**. Once this directory
is copied into a real harness repo's root, `.github/` lands in the right place
for GitHub to auto-load agents, instructions, and skills.

## Prerequisites

- GitHub Copilot **Business** or **Enterprise**, with Cloud Agent
  ("Coding agent") enabled for the harness org.
- GitHub Copilot **Pro+** or above for custom agent definitions.
- `gh` CLI authenticated as a user with write access on the harness repo.
- A **read-only** PAT (or GitHub App installation token) scoped to the
  target orgs/repos.

## One-time setup

1. **Create a new private repo** in the org that will own assessments.
   Suggested name: `code-assessment-harness`.

2. **Copy this directory's contents to the new repo's root.**

   ```bash
   # from the new harness repo's root, after cloning it locally:
   cp -R /path/to/contoso-vibe-engineering/assessment-harness/. .
   chmod +x scripts/*.sh
   git add .
   git commit -m "Initialize assessment harness"
   git push
   ```

3. **Add the read-only PAT as a Copilot secret.**
   Settings → Secrets and variables → **Copilot** (not Actions) →
   New repository secret:
   - Name: `COPILOT_MCP_GITHUB_PAT`
   - Value: a fine-grained PAT with **only** `Contents: Read`,
     `Metadata: Read`, `Pull requests: Read`, `Issues: Read` on the target
     orgs. **No write scopes anywhere.** For >50 targets, prefer a GitHub
     App installation token.

4. **Verify Cloud Agent assignment works** in this repo:

   ```bash
   gh api graphql -f query='
     query { suggestedActors(loginNames: ["copilot-swe-agent"], capabilities: [CAN_BE_ASSIGNED], first: 1) {
       nodes { ... on Bot { id login } ... on User { id login } }
     } }'
   ```

   Should return a non-null `id`. Empty → Cloud Agent isn't enabled here;
   escalate to org admin.

5. **Smoke test with one target** (see "Running an assessment" below).

## Running an assessment

1. **Prepare targets** in `targets.txt` (gitignored):

   ```
   # one owner/repo per line
   octocat/Hello-World
   # your-org/some-app
   # your-org/another-service
   ```

   Use `targets.example.txt` as a starting point.

2. **Kick off the batch:**

   ```bash
   HARNESS_REPO=<owner>/<harness-repo> ./scripts/kickoff-assessments.sh
   ```

   Optional positional args:

   ```bash
   HARNESS_REPO=... ./scripts/kickoff-assessments.sh \
       path/to/targets.txt \
       "Focus only on auth, secrets handling, and CI security scans."
   ```

   Each kickoff:
   - Creates one issue per target titled `assess: <owner>/<repo>`.
   - Assigns Copilot via the `replaceActorsForAssignable` GraphQL mutation
     (with the required `GraphQL-Features` headers).
   - Appends an audit line to `kickoff.log`.

3. **Wait for Cloud Agent PRs.** Each assignment triggers a session that
   opens a `copilot/...` PR adding
   `analyses/<owner>__<repo>/assessment.md`.

4. **Review each PR.** Verify:
   - All 10 rubric sections present (per
     `.github/instructions/assessment-standards.instructions.md`).
   - `Coverage gaps` section is honest.
   - `Evidence` section cites file paths with line ranges.
   - No leaked secrets or PII.

5. **Merge approved PRs.** Merging is the explicit human approval gate
   before sharing with the target app team.

6. **Collect results locally** for archiving or reporting:

   ```bash
   HARNESS_REPO=... ./scripts/collect-results.sh merged
   ```

   Default state is `all`; pass `merged` to only collect human-approved
   assessments. Output goes to `results/<owner>__<repo>/pr-<num>.md`.

## Operator skill

The harness ships with a project-scoped Copilot CLI skill at
`.github/skills/assessment-harness/`. When an operator opens Copilot CLI in
the deployed harness repo, the skill auto-loads and provides guided help for:

- First-time setup
- Adding targets
- Running batches
- Reviewing and collecting results
- Troubleshooting (rate limits, MCP errors, Copilot assignment failures,
  PAT rotation)

Trigger phrases include "kick off assessments", "assess these repos",
"collect results", "Copilot didn't pick up the issue", "MCP can't reach
target", "PAT scope", "rate limited".

The skill's troubleshooting runbook is at
`.github/skills/assessment-harness/references/troubleshooting.md` — it can
also be read directly.

## Caveats and operational guidance

- **Context budget.** GitHub MCP traversal is API-bound and the Cloud Agent
  has a finite session context. Very large monorepos may exceed it — narrow
  focus areas, or split into multiple per-subdirectory issues. The
  `Coverage gaps` section in each assessment is the honest record of what
  the agent couldn't reach.

- **API rate limits.** A fine-grained PAT gets 5,000 requests/hour. For
  batches >50 targets, run in chunks of 25–50 with ~1 hour between, or
  switch to a GitHub App installation token (5,000/hr per installation,
  scaling with installs). The kickoff script does not auto-throttle.

- **PAT scope hygiene.** The agent's hard rules forbid target writes, but
  defense-in-depth says the PAT itself must be read-only. If the PAT has
  any write scope, rotate it immediately. Rotate quarterly regardless.

- **No clones, ever.** The architecture assumes targets are read via API
  only. If a future task needs filesystem-level analysis (e.g. running a
  linter), rethink the pattern — don't add a clone step here.

- **Audit trail.** `kickoff.log` records every issue created. Each Cloud
  Agent session has a transcript linked from the issue page. Together they
  form the audit trail for compliance.

- **Incident response.** If a write ever appears on a target repo,
  immediately rotate `COPILOT_MCP_GITHUB_PAT`, audit the agent definition
  for tampering, and pull the offending session transcript. See the
  troubleshooting reference for the full P0 procedure.

## What's intentionally NOT here

- No GitHub Actions workflow that auto-kicks off assessments. Kickoff is a
  deliberate human-driven step so batch sizes can be controlled.
- No webhooks or pre-merge automation. Human review of every PR is
  load-bearing for the compliance story.
- No clone, fork, or mirror of any target. All target reads are via the
  GitHub API through MCP.
- No write scopes on the PAT. Ever.

## Reference: documents inside the harness

| Document | Purpose |
|----------|---------|
| `.github/agents/code-assessor.agent.md` | Cloud Agent definition with hard read-only rules |
| `.github/instructions/assessment-standards.instructions.md` | 10-section rubric, scoped to `analyses/**/*.md` |
| `.github/copilot-instructions.md` | Repo-level rules for any Copilot work in the harness |
| `.github/skills/assessment-harness/SKILL.md` | Operator skill loaded by Copilot CLI |
| `.github/skills/assessment-harness/references/troubleshooting.md` | Detailed failure-mode runbook |
| `prompts/assess-repo.template.md` | Issue body template with `{{target_owner}}`, `{{target_repo}}`, `{{focus_areas}}` placeholders |
