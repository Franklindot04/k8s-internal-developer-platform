# ADR 0005: Repository and Branch Strategy

## Status

Approved foundational decision.

## Context

The repository was recovered from historical work and now needs a trustworthy workflow. `main` must represent stable, reviewable project state. New implementation should be easy to review and should avoid mixing unrelated platform concerns.

## Decision

Use `main` as the authoritative stable branch. Implement changes on short-lived focused branches and integrate through pull requests. Do not use the old `develop` branch as the primary development branch.

## Rationale

Focused branches and pull requests keep the project reviewable for one maintainer while still allowing future collaborators to rejoin. Keeping `main` stable avoids ambiguity about which branch represents the current approved project state.

## Alternatives Considered

- Revive `develop`: this would add process overhead and revive a stale branch with little current implementation value.
- Long-lived feature branches: these make review and recovery harder and increase divergence risk.
- Direct commits to `main`: fast, but unsuitable for a portfolio-grade project that should demonstrate disciplined change control.

## Consequences

Each implementation stage should have a clear branch, small review boundary, validation evidence, and documentation updates. Larger architectural changes should be split into separate pull requests when possible.

## Follow-Up Implications

Future stages should use names such as `feature/local-cluster-bootstrap`, `feature/gitops-bootstrap`, `feature/golden-path-chart`, and `feature/service-generator`.
