# ADR 0009: Use Always-Reporting Required Check Gates

## Status

Accepted

## Context

The repository protects `main` with required GitHub status checks. Runtime workflows for Kind, Argo CD, and the golden-path Helm chart are expensive enough that path-based fast paths are useful, but workflow-level pull-request `paths` filters can prevent a workflow from starting at all. When a required workflow does not start, its required check context may be missing rather than explicitly passed or failed.

## Decision

Required workflows must start for every pull request. Path relevance is handled inside each workflow by a repository-owned scope classifier. Runtime-heavy jobs execute only when relevant, while a stable final gate job always runs and owns the protected check context.

The final gate fails closed:

- scope detection failure fails the gate
- relevant runtime failure fails the gate
- relevant runtime cancellation fails the gate
- relevant runtime skip fails the gate
- relevant runtime success passes the gate
- irrelevant runtime skip passes the gate

Manual workflow runs execute the runtime validation path by default.

## Consequences

Required check contexts become reliable for unrelated pull requests while expensive runtime proof remains conditional. The workflows become slightly more complex because each heavy workflow now has scope, execution, and gate jobs. The scope classifier must be maintained when runtime dependencies change.

GitHub workflow-skip commit instructions can still suppress workflow execution. This is acceptable because missing required checks should block merge, and maintainers should not use skip instructions on pull requests requiring protected checks.

If the repository later enables GitHub merge queue, the required workflows must be reviewed for `merge_group` trigger support.
