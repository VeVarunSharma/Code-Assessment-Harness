---
applyTo: "analyses/**/*.md"
---

# Assessment standards

Every assessment must follow this exact section structure so downstream
tooling and human reviewers can scan results consistently.

## Required sections (in order)

### 1. `# Assessment: {target_owner}/{target_repo}`

Top-level H1 with the target identifier.

### 2. `## Summary`

Three to five bullets:

- Primary purpose of the codebase (one sentence).
- Primary language(s) and framework(s).
- Approximate scale (LOC ballpark, number of services/modules).
- Activity signal (recent commits in last 90 days; open PR count).
- Overall risk level: `low` | `medium` | `high` | `unknown` (with one-line
  justification).

### 3. `## Architecture overview`

- Top-level component breakdown (services, libraries, apps).
- Entry points and how requests/data flow through the system.
- External dependencies (databases, queues, third-party APIs) inferred from
  config/manifests.
- Deployment target if discoverable (cloud, on-prem, container platform).

### 4. `## Dependencies & supply chain`

- Package managers in use.
- Notable dependencies (frameworks, ORMs, auth libs, AI SDKs).
- Any **pinned versions known to be vulnerable** (cite CVE if obvious;
  otherwise flag as "needs scan").
- Lockfile presence per ecosystem.

### 5. `## Security posture`

- Auth/authz mechanism if visible.
- Secrets handling (env vars, vault, hardcoded — flag any hardcoded).
- Input validation patterns.
- Presence of CI security scans (CodeQL, Dependabot, secret scanning,
  third-party SAST/DAST).
- Public-facing surface area (HTTP routes, webhook handlers).

### 6. `## Testing & quality`

- Test framework(s) and approximate coverage signal (presence of test
  directories, CI test jobs).
- Linting / formatting / type-checking config.
- CI/CD setup (build, test, deploy stages).

### 7. `## Modernization opportunities`

- Outdated framework versions.
- Patterns that suggest tech debt (god classes, no test coverage on critical
  paths, deprecated APIs).
- Quick wins vs. larger refactors, separated into two sub-bullets.

### 8. `## Program fit & compliance notes`

- Compliance regimes relevant to the operator's rollout (e.g., GDPR,
  HIPAA, SOC2, PCI-DSS, regional privacy laws) — flag anything that
  looks like sensitive-data handling, PII, or data-residency risk.
- Program-fit signals — anything that suggests this codebase is or
  isn't a candidate for the operator's modernization, security, or
  assessment program (size, cohesion, current state, ownership clarity).

> Operators MAY scope this section to a specific compliance regime or
> program by editing this rubric file before kicking off a batch
> (e.g., replace the bullets with HIPAA-specific or GDPR-specific
> checks). If unscoped, the agent should surface candidate concerns
> generically and let the human reviewer route them.

### 9. `## Coverage gaps`

Honest list of directories or concerns you could not analyze due to context
budget, access errors, or ambiguity. **Always include this section** even if
the body is "None."

### 10. `## Evidence`

Bulleted list of the specific files and line ranges you cited above.
Format each as: `- {path} (lines {a}–{b}): {one-line note}`.

## Style rules

- Be direct. No marketing language.
- Cite file paths as backticked code spans.
- If you don't know, say "unknown" — never speculate.
- Keep each section under ~30 lines unless the codebase genuinely needs more.
- Ratings (`low`/`medium`/`high`) must be backed by at least one cited file.
