Assess the external target repository **{{target_owner}}/{{target_repo}}**
using the `code-assessor` custom agent.

## Target

- Owner: `{{target_owner}}`
- Repo:  `{{target_repo}}`
- URL:   https://github.com/{{target_owner}}/{{target_repo}}

## Focus areas

{{focus_areas}}

## Constraints (reminder)

- **Read-only** on the target — use `github-mcp-server` reads only.
- **Never** create issues, branches, PRs, or commits on the target.
- Write the assessment to
  `analyses/{{target_owner}}__{{target_repo}}/assessment.md` in THIS harness
  repo and open the standard `copilot/...` PR back here.
- Follow `.github/instructions/assessment-standards.instructions.md` exactly.
- Close this issue from your PR (`Closes #THIS_ISSUE`).
