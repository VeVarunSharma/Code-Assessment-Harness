# Assessment: VeVarunSharma/contoso-vibe-engineering

## Summary

- **Purpose:** Teaching/demo monorepo that illustrates the transition from "legacy vibe coding" (insecure shortcuts) to "multiplayer vibe engineering" (secure, production-quality patterns) via side-by-side contrast in a single Turborepo.
- **Languages & frameworks:** TypeScript/JavaScript throughout (Next.js 15 App Router + React 19 frontend; Node.js/Express and Hono backend; ASP.NET Core 9 for the logistics service); Terraform (HCL) for IaC.
- **Scale:** ~5 apps/services, 3 shared packages, 1 Terraform module; estimated ~15 000–25 000 LOC (TypeScript/JavaScript dominant; pnpm-lock.yaml ~490 KB indicates a large transitive dependency graph); 200+ merged PRs in commit history.
- **Activity:** Extremely active — 50 commits in the last several days (bulk via Dependabot batch merges); ~305 currently open PRs (majority Dependabot); sole committer is `VeVarunSharma`.
- **Overall risk: medium** — the codebase deliberately ships SQL-injection-vulnerable endpoints (`app/api/legacy-vibe/`) and header-only mock auth on the medical API (`X-User-Id`/`X-User-Role` headers with a TODO to replace with real JWT). Both are labeled as demo/teaching artifacts, but they increase the blast radius if the app is ever deployed as-is.

---

## Architecture overview

**Top-level components:**

| Layer | Name | Technology |
|-------|------|------------|
| Frontend app | `apps/contoso-web-app` | Next.js 15, React 19, Tailwind CSS 4, shadcn/ui |
| Frontend app | `apps/octocat-blog-app` | Next.js + PostgreSQL + Drizzle ORM |
| Frontend app | `apps/octocat-support-app` | Next.js + GitHub Copilot SDK (AI triage) |
| Backend service | `services/platform-api` | Express 4, Drizzle ORM, PostgreSQL, Zod |
| Backend service | `services/medical-api` | Hono, Drizzle ORM, PostgreSQL, Zod (PIPA BC) |
| Backend service | `services/ai-tool-digest` | Azure Function (Dockerized) |
| Full-stack service | `services/rigidport` | ASP.NET Core 9, Razor Pages, EF Core, SQLite |
| Shared packages | `packages/ui`, `packages/eslint-config`, `packages/typescript-config` | shadcn/ui, ESLint, TypeScript |
| IaC | `infra/terraform/azure-vancouver-example` | Terraform, Azure |

**Request flow:**
- Next.js Server Components and API Routes (`app/api/`) handle both SSR and HTTP endpoints.
- `contoso-web-app` routes split into `legacy-vibe/` (intentionally vulnerable) and `secure-vibe/` (Drizzle + Zod).
- Backend services run independently; frontends call them over HTTP (CORS enabled on all services).
- `octocat-support-app` proxies ticket creation to GitHub Issues via `@github/copilot-sdk`.

**External dependencies inferred from config:**
- PostgreSQL (platform-api, medical-api, octocat-blog-app via docker-compose)
- SQLite (rigidport — EF Core)
- Azure (AI Tool Digest Azure Function, Terraform targets Azure)
- GitHub API (octocat-support-app issue creation)

**Deployment target:** Azure cloud (Terraform in `infra/terraform/azure-vancouver-example`); CI/CD via both GitHub Actions and Azure Pipelines (`azure-pipelines.yml`).

---

## Dependencies & supply chain

- **Package manager:** pnpm 10.26.2 (locked); `pnpm-lock.yaml` present at root.
- **Build orchestration:** Turborepo 2.5.5.
- **Notable production dependencies:**
  - `next@15.5.15`, `react@19.1.1` — current, bleeding-edge.
  - `drizzle-orm@^0.30.9` — type-safe ORM for PostgreSQL; security patch PR (#305) open for update.
  - `hono` — lightweight web framework for medical-api; security patch PR (#305) open.
  - `express@^4.21.2` — Express 4 in platform-api; Express 5 is available but not adopted.
  - `zod@^3.23.4` / `^3.25.76` — schema validation across apps.
  - `@github/copilot-sdk` — AI triage in octocat-support-app.
  - `nodemailer@^8.x` — email notifications (merged dependency bump visible in commits).
  - **NuGet:** `RigidPort` service tracks .NET 9 packages; Dependabot configured.
- **Lockfile presence:** Yes — `pnpm-lock.yaml` (npm/pnpm), `apm.lock.yaml` (APM packages), NuGet lockfile implied by Dependabot NuGet config.
- **Vulnerable/stale versions:**
  - PR #305 groups `drizzle-orm` and `hono` as `security-patches` — **pending merge**, not yet applied to `main`.
  - `express@^4.x` remains at v4; no flagged CVE found in sampled data but express 4 has known past advisories.
  - A `pnpm audit --audit-level=high` step exists in Azure Pipelines (`continueOnError: true`) — results are not blocking.
- **Dependabot coverage:** Comprehensive — npm (all workspace directories), GitHub Actions, Docker, Docker Compose, pip, NuGet, Terraform; grouped by `security-patches` applying to all ecosystems.

---

## Security posture

- **Auth/authz:**
  - `services/medical-api` has `requireAuth` and `requireRole` middleware enforcing role-based access (`physician`, `nurse`, `admin`, `billing`, `receptionist`). **However, the auth implementation is header-only mock** (`X-User-Id`, `X-User-Role` HTTP headers), with an explicit `TODO: In production, implement real JWT validation`. No JWT verification library is present.
  - `services/platform-api` (Express) has no auth middleware visible in sampled routes (`/health`, `/users`). Endpoints are publicly accessible.
  - `apps/contoso-web-app` frontend has no session/auth mechanism; the intentionally insecure routes are the teaching point.

- **Secrets handling:**
  - `.github/secret_scanning.yml` is present (GitHub secret scanning enabled).
  - No hardcoded secrets found in sampled source files; credentials are referenced via `process.env` and `.env` files (`.gitignore` excludes `.env`).
  - Azure Pipelines variables (`TURBO_TEAM`, `TURBO_TOKEN`) are passed as pipeline variables, not hardcoded.
  - PIPA BC compliance workflow requires a `COPILOT_GITHUB_TOKEN` secret; properly stored as an Actions secret.

- **Input validation:**
  - Secure-vibe routes use Zod for schema validation.
  - Legacy-vibe routes deliberately bypass validation (SQL injection by design, per README).
  - `medical-api` uses Zod on patient routes (inferred from package.json dependency and PIPA doc requirements).

- **CI security scans:**
  - **CodeQL:** Active on push/PR to `main` and weekly schedule; covers `javascript-typescript` and `csharp`.
  - **Dependabot:** Active across all ecosystems.
  - **Dependency Review:** `dependency-review.yml` runs on PRs.
  - **PIPA BC Compliance:** Copilot-CLI-driven compliance check on `services/medical-api/**` changes.
  - **SOC-2 Compliance:** `soc-2-compliance.lock.yml` exists (locked/frozen agent workflow).
  - **`pnpm audit` in Azure Pipelines:** `continueOnError: true` — failures do not block merges.
  - No DAST/SAST beyond CodeQL detected.

- **Public-facing surface:**
  - Next.js API routes under `app/api/legacy-vibe/` are intentionally insecure; they must not be deployed to production as-is.
  - `cors()` called with defaults (allow-all origins) on both platform-api and medical-api — wide open for a service handling PHI.
  - platform-api exposes `/users` with no auth.

---

## Testing & quality

- **Test frameworks:**
  - Jest 29 + `@swc/jest` (fast transpilation) + `@testing-library/react` — used in `contoso-web-app` and `octocat-blog-app`.
  - Playwright — E2E configured for `contoso-web-app` (`config/playwright/playwright.config.ts`).
  - `dotnet test` + xUnit implied by `rigidport-tests.yml` workflow.

- **CI test jobs:**
  - `contoso-web-app-unit-tests.yml`, `octocat-blog-app-unit-tests.yml`, `rigidport-tests.yml` — dedicated per-service test workflows.
  - Azure Pipelines runs `pnpm test` and publishes JUnit + Cobertura coverage reports.

- **Linting / formatting / type-checking:**
  - ESLint via shared `@workspace/eslint-config`; per-app `eslint.config.js`.
  - Prettier configured at root (`prettier --write "**/*.{ts,tsx,md}"`).
  - TypeScript strict mode enforced via `@workspace/typescript-config`; `tsc --noEmit` typecheck scripts present.
  - Separate `octocat-blog-app-lint.yml` and `octocat-blog-app-typecheck.yml` workflows.

- **Coverage signal:** Cobertura XML is published from Azure Pipelines for Next.js apps; no coverage threshold enforcement visible. `services/platform-api/` and `services/medical-api/` have no test directories — estimated **0% test coverage** for both backend services beyond lint.

- **Gap:** Frontend apps (Next.js) have Jest + Playwright coverage. Backend services (`platform-api`, `medical-api`) have no unit or integration tests in the sampled directories.

---

## Modernization opportunities

**Quick wins:**
- Replace mock header-based auth in `medical-api` (`requireAuth`) with real JWT validation (e.g., `hono/jwt` or a dedicated JWKS middleware). This is a single-file change already stubbed out.
- Set `pnpm audit` to `continueOnError: false` in Azure Pipelines so security audit failures block merges.
- Pin CORS on `medical-api` and `platform-api` to specific allowed origins rather than the allow-all default.
- Merge open security-patch PR #305 (`drizzle-orm`, `hono` updates).

**Larger refactors:**
- Add auth middleware to `platform-api` (currently no authentication on `/users` endpoint).
- Add integration/unit test suites for `services/platform-api` and `services/medical-api` — both lack any test directory.
- Evaluate Express 4 → Express 5 migration for `platform-api` (Express 5 is now stable).
- `services/rigidport` (ASP.NET Core + SQLite) is architecturally inconsistent with the rest of the polyglot stack; assess whether it should be a separate repo or aligned to a common deployment model.
- Replace the `dotnet-to-angular-agent` service (migration agent) with documented usage instructions; agentic migration tooling in a monorepo adds maintenance burden.

---

## Program fit & compliance notes

- **PIPA BC (British Columbia Personal Information Protection Act):**
  - `services/medical-api` explicitly targets PIPA BC compliance with a `PIPA_COMPLIANCE.md`, dedicated middleware (`audit.ts`, `auth.ts`, `consent.ts`), and an automated compliance check workflow (`pipa-bc-compliance.yml`).
  - The mock auth implementation (header-only, no JWT) is a **critical gap** for any real PIPA BC deployment: unauthenticated callers can trivially forge `X-User-Role` headers and access PHI.
  - CORS allow-all on the medical-api compounds this — any browser origin can call patient endpoints.
  - Audit logging middleware is present (`audit.ts`), which is a positive PIPA BC signal.

- **SOC-2:**
  - A `soc-2-compliance.lock.yml` workflow exists, suggesting SOC-2 controls are being evaluated or documented. The `.lock.yml` convention appears to be a frozen AI-generated workflow — review whether it is actively enforced.

- **HIPAA / GDPR:**
  - Not explicitly referenced, but `medical-api` handles patient data (`patients.ts` route, PHI fields). If deployed in a US or EU context, HIPAA / GDPR obligations apply. Currently unaddressed.

- **Program fit:**
  - Strong candidate for a security-modernization or AI-assisted development program — the repo is structured explicitly to demonstrate before/after security posture.
  - Ownership is clearly a single developer (`VeVarunSharma`); bus-factor is 1. CODEOWNERS file exists but likely maps to the same individual.
  - The polyglot nature (TypeScript, C#, Python, HCL) increases assessment and tooling surface area.
  - The intentionally vulnerable `legacy-vibe` routes must be isolated or removed before any production deployment.

---

## Coverage gaps

- `services/ai-tool-digest` (Azure Function) — directory structure not sampled; Dockerfile and function code not reviewed.
- `services/rigidport` — ASP.NET Core source not sampled beyond package listing; EF Core migrations not inspected.
- `apps/octocat-blog-app` and `apps/octocat-support-app` — package.json and route structure not read; AI triage logic not reviewed.
- `apps/contoso-web-app/app/api/legacy-vibe/` route handler — not read; SQL injection pattern confirmed by README description only.
- `apps/contoso-web-app/app/api/secure-vibe/` route handler — not read.
- `services/medical-api/src/routes/patients.ts` — not read; route-level auth enforcement not confirmed.
- `infra/terraform/azure-vancouver-example/api-service/` — Terraform `.tf` files not sampled; resource definitions unknown.
- `.github/workflows/multi-model-code-review.yml` — large workflow (24 KB); contents not read.
- `pnpm-lock.yaml` — too large (500 KB) to read; specific pinned versions of transitive deps not verified against CVE databases.

---

## Evidence

- `README.md` (lines 1–110): Tech stack table, repo structure, app descriptions, confirmed intentional SQL injection in legacy-vibe.
- `package.json` (root, all lines): pnpm 10.26.2, Turborepo 2.5.5, TypeScript 5.9.2, Prettier.
- `apps/contoso-web-app/package.json` (all lines): Next.js 15.5.15, React 19.1.1, Zod, Jest 29, Playwright.
- `services/platform-api/package.json` (all lines): Express 4.21.2, Drizzle ORM 0.30.9, Zod 3.23.4, no auth library.
- `services/medical-api/src/index.ts` (all lines): Hono app, CORS allow-all, single `/api/patients` route, PIPA BC error-hiding note.
- `services/medical-api/src/middleware/auth.ts` (all lines): Header-only mock auth (`X-User-Id`/`X-User-Role`), explicit TODO for JWT, RBAC role definitions.
- `services/platform-api/src/server.ts` (all lines): Express app, CORS allow-all, no auth middleware.
- `.github/workflows/codeql.yml` (all lines): CodeQL on push/PR/weekly, JS-TS + C# languages.
- `.github/dependabot.yml` (all lines): Full multi-ecosystem Dependabot config with security-patch grouping.
- `.github/workflows/pipa-bc-compliance.yml` (all lines): Copilot-CLI-driven PIPA BC check on medical-api PRs; 80% score threshold.
- `azure-pipelines.yml` (all lines): Build + test + `pnpm audit --audit-level=high` (non-blocking).
- `SECURITY.md` (all lines): Responsible disclosure policy, private vulnerability reporting configured.
- `.github/secret_scanning.yml` (path): Secret scanning config present.
- `.github/workflows/dependency-review.yml` (path): Dependency review workflow present.
- `services/medical-api/PIPA_COMPLIANCE.md` (path): PIPA BC compliance documentation present.
- `apps/contoso-web-app/app/legacy-vibe/` (directory listing): Single `page.tsx` confirmed — intentionally insecure UI entry point.
- `apps/contoso-web-app/app/api/` (directory listing): Separate `legacy-vibe/` and `secure-vibe/` API route directories.
- `.github/workflows/` (directory listing): 17 workflow files covering tests, CodeQL, PIPA BC, SOC-2, dependency review, multi-model code review.
- `infra/terraform/azure-vancouver-example/` (directory listing): Single `api-service/` module; Azure deployment target confirmed.
