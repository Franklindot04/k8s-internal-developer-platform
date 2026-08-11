# ADR 0004: Use Kyverno for Policy-as-Code

## Status

Approved foundational decision.

## Context

The platform needs Kubernetes policy enforcement that can be understood, tested, and demonstrated locally. Policies should cover security and reliability expectations without requiring a separate policy language for the first platform version.

## Decision

Use Kyverno for Kubernetes policy enforcement and policy testing.

## Rationale

Kyverno policies are Kubernetes resources, which makes them approachable for a Kubernetes-focused platform project. Kyverno can validate, mutate, and generate resources, and it supports policy testing workflows suitable for CI.

## Alternatives Considered

- OPA Gatekeeper: mature and powerful, especially for organizations already invested in Rego.
- Admission webhooks built in-house: flexible but unnecessarily complex for this project.
- Documentation-only policy: insufficient because the project must demonstrate executable controls.

## Consequences

Policies should be introduced after the platform has a reproducible cluster and workload contract. Policy failures must be tested and documented so the platform shows enforceable behavior.

## Follow-Up Implications

Stage 7 should add Kyverno installation, baseline policies, policy tests, and examples of accepted and rejected workloads.
