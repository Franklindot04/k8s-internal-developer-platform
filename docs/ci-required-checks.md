# Required Check Governance

Required pull-request checks must report a stable status context on every pull request. A workflow-level `paths` or `paths-ignore` filter can prevent the workflow from starting, which can leave a required check context absent instead of passed or failed.

## Model

Runtime-heavy workflows use an always-starting pull-request trigger and move path relevance decisions inside the workflow:

1. Scope detection runs on every pull request.
2. Runtime execution runs only when the changed files are relevant.
3. A stable final gate always runs and reports the required check context.

The final gate fails closed. It fails when scope detection fails, when relevant runtime execution fails, when relevant runtime execution is cancelled, or when relevant runtime execution is unexpectedly skipped. It succeeds when relevant runtime execution succeeds, or when runtime execution is intentionally skipped for irrelevant changes.

Manual `workflow_dispatch` runs execute the full runtime path by default.

## Scope Dependency Hierarchy

The Kind lifecycle is the runtime foundation. Changes to Kind configuration, Kubernetes lifecycle scripts, the Kubernetes tool installer, Make targets, or shared scope logic require Kind validation.

The GitOps control plane depends on Kind. Changes to GitOps configuration, GitOps scripts, platform bootstrap state, Kind dependencies, Make targets, or shared scope logic require Argo CD reconciliation validation.

The golden-path Helm workflow depends on GitOps and Kind. Changes to the chart, Helm tooling, golden-path GitOps manifests, golden-path scripts, GitOps dependencies, Kind dependencies, Make targets, or shared scope logic require Helm chart and GitOps validation.

Ordinary unrelated documentation changes use the fast path: repository validation still runs, runtime-heavy execution jobs are skipped, and final gates report success.

## Current Checks

Current required `main` checks:

- `Validate repository baseline`
- `Kind lifecycle validation`
- `Argo CD reconciliation validation`

Future eligible check after governance proof:

- `Helm chart and GitOps validation`

## Workflow Skip Instructions

GitHub commit-message skip instructions such as `skip ci` can still suppress pull-request workflows. Maintainers should not use workflow-skip instructions on pull requests that need required checks. If a required workflow is suppressed, the missing required context should block merge.

Do not use `pull_request_target` to bypass this behavior.

## Merge Queue

This repository does not currently have a merge queue configured. `merge_group` triggers are not required yet. If a merge queue is enabled later, required workflows should be reviewed and updated as a focused governance change.

## Future Required Checks

Any future required check should use an always-reporting final gate with the protected status-check name. Expensive setup and runtime proof may be conditional, but the final required context must not be hidden behind workflow-level pull-request path filters.

Before a new heavy runtime gate is promoted to required status, verify both paths on real pull requests: relevant changes must execute runtime validation and report through the final gate, while irrelevant changes must skip runtime validation intentionally and still report final-gate success.
