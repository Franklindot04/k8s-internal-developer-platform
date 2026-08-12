# ADR 0011: Compile PlatformService Intent Into Deterministic Golden-Path Values

## Status

Accepted for Stage 5B review.

## Context

Stage 5A established the strict `idp/v1alpha1` `PlatformService` contract. The next platform boundary is proving that validated developer intent can consume the Stage 4 golden-path Helm chart API without exposing raw Helm values to developers.

Stage 4 already owns the Kubernetes implementation details: Deployment, Service, ServiceAccount, ConfigMap, PodDisruptionBudget, probes, resources, and optional HPA/Ingress/NetworkPolicy behavior. Stage 5B should compile into that existing API rather than modifying the chart or creating Kubernetes manifests directly.

## Decision

Introduce a deterministic compilation layer:

```text
validated PlatformService
-> normalized intent
-> platform-owned profile policy
-> minimal golden-path values model
-> deterministic YAML rendering
```

The compiler maps only developer-derived values, platform-policy-derived values, and explicit invariants required by `PlatformService` v1alpha1. All other golden-path values inherit Stage 4 defaults.

Resource and availability profile semantics live in `platform/self-service/profile-policy.yaml`. The compiler validates that policy against the service schema profile enums so the contract and runtime policy cannot silently drift.

Add `platformctl service plan <service.yaml>` as a read-only command. It prints the future canonical output path and rendered values for review, but it does not write repository files.

## Rationale

Stage 4 remains the implementation API because it is already validated through Helm schema, Helm lint, Helm template rendering, kubeconform, and runtime reconciliation in earlier stages. Duplicating that API under Stage 5 would create two places for Kubernetes behavior to drift.

Developer intent exposed by `PlatformService` v1alpha1 must be representable by the current Stage 4 workload API. For example, the public runtime port contract is aligned to the golden-path chart's `containerPort.port` bounds of `1024` through `65535` so a service that passes validation does not fail planning because of a statically known chart constraint.

Generated values are minimal to keep the platform, not each service, responsible for security contexts, ServiceAccount hardening, probe timing, scheduling, revision history, termination behavior, NetworkPolicy details, and optional feature knobs.

Profile policy is platform-owned because developers should choose intent such as `small` or `standard`, not raw CPU, memory, PDB syntax, or HPA tuning. The current mappings are demo/default operating profiles suitable for local validation, not universal production capacity recommendations.

Autoscaling and external exposure remain excluded because `PlatformService` v1alpha1 does not expose those capabilities and the current platform has not proven their full lifecycle as developer self-service features.

Rendering is deterministic so future generated files can be reviewed, compared, regenerated, and eventually drift-checked without timestamps, random data, current-user data, commit SHAs, or filesystem-dependent output.

Stage 5B adds `plan` but not writes because repository mutation, overwrite behavior, atomic generated-directory replacement, and drift detection need their own review boundary after deterministic rendering is proven.

Stage 4 Helm schema and Helm rendering remain the compatibility authority for generated values. Stage 5B tests render representative compiled values through the actual chart rather than maintaining a second values schema.

## Consequences

Developers can preview exactly what their service intent would compile into.

The future write path is fixed as:

```text
services/<service>/generated/values.yaml
```

The handwritten source remains:

```text
services/<service>/service.yaml
```

Stage 5B does not create Argo CD Applications, AppProjects, GitOps registration, generated output drift detection, service deletion, environment overlays, or Stage 6 supply-chain behavior.

The current Stage 4 chart accepts container ports from `1024` through `65535`. The PlatformService schema uses the same bounds, while the compiler retains a defensive internal check against the chart schema.

## Alternatives Considered

- Generate raw Kubernetes manifests: rejected because it bypasses the Stage 4 golden-path chart and duplicates platform ownership.
- Copy the full `values.yaml` into every service: rejected because most chart settings are platform defaults, not developer intent.
- Store profile mappings only in Python conditionals: rejected because policy should be visible and reviewable without reading compiler code.
- Implement `generate` immediately: rejected because write behavior, overwrite safety, and drift detection deserve a later implementation slice.
- Reuse the historical shell renderer: rejected because Stage 5B is structured-data compilation, not string substitution.
