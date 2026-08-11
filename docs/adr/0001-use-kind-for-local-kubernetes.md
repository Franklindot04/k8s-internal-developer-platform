# ADR 0001: Use Kind for Local Kubernetes

## Status

Approved foundational decision.

## Context

The platform needs a reproducible Kubernetes environment that can be demonstrated locally without mandatory cloud infrastructure. The environment should be fast enough for iterative development and simple enough for one maintainer to operate.

## Decision

Use Kind as the primary local Kubernetes environment.

## Rationale

Kind provides Kubernetes clusters in containers, has broad community usage, integrates well with CI and local developer workflows, and keeps the project independent from a cloud account for the primary demonstration path.

## Alternatives Considered

- Minikube: capable and developer-friendly, but Kind is lighter for declarative cluster lifecycle and CI-style workflows.
- k3d: also strong for local clusters, but Kind aligns well with upstream Kubernetes conformance testing patterns.
- Managed cloud Kubernetes: useful for a future reference architecture, but it would make the main demonstration depend on cloud spend and provider-specific setup.

## Consequences

The platform will need Kind cluster configuration, bootstrap scripts, validation, teardown, and documented prerequisites in a later stage. Cloud portability should remain an explicit design consideration, but not a Stage 1 implementation requirement.

## Follow-Up Implications

Stage 2 should add deterministic Kind lifecycle automation and validation. Later GitOps, policy, observability, and workload stages should prove their behavior on this local cluster.
