# ADR 0002: Use Argo CD for GitOps

## Status

Approved foundational decision.

## Context

The platform needs a GitOps control plane that can reconcile desired state from the repository into Kubernetes. The project should demonstrate clear application registration, reconciliation, drift visibility, and promotion workflows.

## Decision

Use Argo CD as the GitOps engine.

## Rationale

Argo CD is widely used, Kubernetes-native, visible in demos, and well suited for application-of-applications or structured platform bootstrap patterns. It gives the project a clear reconciliation model without requiring custom deployment logic.

## Alternatives Considered

- Flux: a strong GitOps option with a compact controller model and good automation support.
- Plain `kubectl apply`: useful for early validation, but it does not demonstrate reconciliation or drift management as a platform capability.
- Custom deployment scripts: flexible, but they would add avoidable maintenance burden and weaken the GitOps story.

## Consequences

Argo CD configuration must be introduced deliberately in a later stage with least-privilege access, clear environment boundaries, and a documented bootstrap path.

## Follow-Up Implications

Stage 3 should define the Argo CD installation, root application structure, application registration model, validation commands, and rollback guidance.
