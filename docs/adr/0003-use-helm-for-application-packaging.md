# ADR 0003: Use Helm for Application Packaging

## Status

Approved foundational decision.

## Context

The platform needs a reusable application packaging standard. The standard must express Kubernetes deployment concerns such as labels, probes, resources, services, security contexts, autoscaling, disruption handling, networking, and observability integration.

## Decision

Use Helm for the platform golden-path application chart.

## Rationale

Helm is a common Kubernetes packaging tool, supports values schemas, can be linted and rendered locally, and is familiar to many platform and application teams. It is suitable for a portfolio project that needs to show practical deployment contracts.

## Alternatives Considered

- Kustomize: strong for overlays and patching, but less direct for a reusable service chart contract.
- Raw Kubernetes YAML: transparent, but difficult to reuse consistently across services.
- Jsonnet or CUE: powerful, but would add more specialized tooling than this project needs at the foundation stage.

## Consequences

The historical Helm branch should not be merged wholesale. Its coverage areas can inform a new chart, but the chart must be reimplemented with rendering tests, schema validation, correct labels/selectors, and secure defaults.

## Follow-Up Implications

Stage 4 should create the golden-path chart and prove it with `helm lint`, rendered manifest review, Kubernetes schema validation, and meaningful chart tests.
