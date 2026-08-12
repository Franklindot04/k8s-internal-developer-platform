# ADR 0010: Adopt a Versioned PlatformService Intent Contract

## Status

Accepted for Stage 5A implementation.

## Context

Stage 5 adds developer self-service on top of the Stage 4 golden-path Helm chart. The platform needs a stable developer intent contract before it implements generators, GitOps registration, or any future portal/API layer.

The historical `feature/service-template-generator` branch contains useful evidence of intent, but its shell generator is placeholder-heavy, non-deterministic, and disconnected from the recovered Stage 1-4 architecture. It should remain preserved as historical evidence rather than being merged wholesale.

## Decision

Adopt a strict file-based service contract:

```yaml
apiVersion: idp/v1alpha1
kind: PlatformService
```

The contract is repository-owned and versioned. It is not a Kubernetes CRD and does not use a DNS-style API group. `PlatformService` is used instead of `Service` because the file is not a Kubernetes core Service.

Stage 5A validates this contract with JSON Schema plus a small Python semantic validation layer. Python is selected because it handles structured YAML, JSON Schema validation, readable CLI errors, and focused unit tests without forcing shell string substitution into a platform API.

## Rationale

Contract-first design keeps the self-service model independent of the eventual interface. A CLI, portal, API, or service catalog can later read and write the same `PlatformService` file without redefining developer intent.

The v1alpha1 contract is deliberately strict. Unknown fields fail validation so developers cannot accidentally depend on raw Helm values, Kubernetes objects, Argo CD internals, or speculative future platform capabilities.

The image digest is mandatory because the Stage 4 chart already demonstrates immutable image support and rejects unsafe floating `latest` usage. Stage 6 may later automate image production and digest updates, but v1alpha1 should not accept ambiguous tag-only runtime definitions.

The image repository and digest are separate authority fields. The repository value is validated so it cannot smuggle an embedded tag, embedded digest, URL scheme, empty path segment, trailing slash, or whitespace.

The exposed runtime surface is limited to image, port, health path, resource profile, availability profile, non-secret config, and existing Secret references. Autoscaling, external exposure, raw NetworkPolicy, scheduling controls, ServiceAccount annotations, extra volumes, and raw commands remain outside normal v1alpha1 self-service.

Stage 4 remains the Kubernetes implementation layer. Later Stage 5 slices will derive Helm values and GitOps-ready Application manifests from `PlatformService` input. Generated artifacts must not become competing sources of truth.

## Consequences

Developers get a small, reviewable contract that avoids Kubernetes implementation detail.

Platform maintainers keep control of security contexts, selectors, PDB/HPA mapping, namespace conventions, AppProject boundaries, and chart evolution.

The first Stage 5 implementation slice can validate service intent without prematurely generating files, deploying workloads, adding Argo CD registration, or beginning Stage 6 supply-chain work.

Future contract changes must either be backwards compatible within `idp/v1alpha1` or introduced through a new version with an explicit migration path.

## Alternatives Considered

- Reuse the historical shell generator: rejected because it relies on string substitution, placeholder functions, non-deterministic timestamps, and stale architecture assumptions.
- Expose raw Helm values: rejected because it would make the chart API and developer self-service API the same thing.
- Use `kind: Service`: rejected because it would be confused with a Kubernetes core Service.
- Add a CRD immediately: rejected because Stage 5 only needs a repository file contract at this stage.
- Build a portal first: rejected because a portal should be an interface over a stable contract, not the place where the contract is invented.
