# ADR 0012: Generate PlatformService GitOps Applications

## Status

Accepted for Stage 5C review.

## Context

Stage 5A established the strict `idp/v1alpha1` `PlatformService` contract. Stage 5B proved that validated intent can compile into deterministic Stage 4-compatible Helm values without writing repository files.

The remaining Stage 5 GitOps boundary is proving that the same intent can also produce an Argo CD `Application` artifact that points at the Stage 4 golden-path chart and the future service-specific generated values file. The artifact must align with the Stage 3 GitOps control-plane contract and the Stage 4 golden-path workload contract without widening either existing project boundary.

## Decision

Introduce a deterministic GitOps compilation layer:

```text
validated PlatformService
-> normalized intent
-> platform-owned GitOps policy
-> deterministic Argo CD Application YAML
```

The policy lives in `platform/self-service/gitops-policy.yaml`. It pins the platform repository URL, chart path, target revision, Argo CD namespace, destination server, namespace prefix, generated output names, sync options, and the `self-service` AppProject name.

Add a platform-owned AppProject at `infra/gitops/self-service/appproject.yaml`. It allows only the platform repository, only the in-cluster Kubernetes API, and only `svc-*` destinations. Its cluster-resource whitelist restricts Namespace creation to names matching `svc-*`. Its namespaced resource whitelist matches the Stage 5B default output surface: ConfigMap, Service, ServiceAccount, Deployment, and PodDisruptionBudget.

Update `platformctl service plan <service.yaml>` to remain read-only while printing both future artifacts:

```text
services/<service>/generated/values.yaml
services/<service>/generated/application.yaml
```

The generated Application uses:

- `metadata.namespace: argocd`
- `spec.project: self-service`
- `spec.source.repoURL`: the platform repository
- `spec.source.targetRevision: main`
- `spec.source.path: platform/helm-charts/golden-path`
- `spec.source.helm.releaseName`: the service name
- `spec.source.helm.valueFiles`: one repository-relative path back to the future values file
- `spec.destination.server: https://kubernetes.default.svc`
- `spec.destination.namespace: svc-<service>`
- automated prune and self-heal with `CreateNamespace=true` and `PruneLast=true`

## Rationale

The generated Application is intentionally service-specific and explicit. It avoids ApplicationSet, app-of-apps discovery, controller-side generation, and automatic registration so this slice can focus on deterministic artifact shape and policy boundaries.

Using `targetRevision: main` preserves the committed desired-state contract used by earlier GitOps manifests. CI or later automation may still substitute immutable SHAs in runtime validation, but generated repository artifacts remain stable and reviewable.

The values file path is computed relative to the chart directory and then canonicalized back into the repository. This prevents absolute paths and path traversal from entering generated Argo CD configuration.

The service namespace is derived as `svc-<service>`. The existing service-name limit leaves room under the Kubernetes 63-character name limit while keeping service ownership visible at the namespace boundary.

The AppProject excludes Secrets, Ingresses, HPAs, NetworkPolicies, wildcard repositories, wildcard clusters, and broad namespaces because those capabilities are not part of `PlatformService` v1alpha1 or the Stage 5B default values output.

Application resources reside in the Argo CD control-plane namespace in this repository's declarative model, matching Stage 3 and Stage 4. That placement is not a developer permission boundary. The AppProject governs destination and resource permissions for reconciled workloads; it does not make arbitrary writes to the Argo CD namespace safe. Developers do not receive direct Argo CD namespace write access, direct Application registration, arbitrary project selection, or arbitrary namespace selection.

Stage 5C also introduces a non-required `Service GitOps` workflow for clean-runner runtime proof after PR publication. The workflow uses the real compiler, substitutes only the immutable tested revision, and uses the existing compiler-backed `minimal-single` golden values artifact outside the chart directory to prove Argo CD cross-directory Helm values resolution. The deterministic production compiler still emits `targetRevision: main` and the production values path `../../../services/<service>/generated/values.yaml`.

## Consequences

Developers can preview the exact values and GitOps Application that future generation will write.

The handwritten source remains:

```text
services/<service>/service.yaml
```

The future generated files are:

```text
services/<service>/generated/values.yaml
services/<service>/generated/application.yaml
```

Stage 5C does not implement repository writes, overwrite behavior, drift detection, service deletion, automatic Argo CD registration, app-of-apps, ApplicationSet, environment overlays, or Stage 6 image supply-chain behavior.

There are three proof levels. Stage 5B tests prove the selected values artifact is byte-exact compiler output from the matching `PlatformService`. Stage 5C unit and path tests prove deterministic production Application rendering and safe production values-path resolution inside the repository. The non-required runtime workflow proves Argo CD can reconcile an Application using the committed Stage 5B compiler-backed golden values artifact outside the chart directory under the `self-service` AppProject. Because Stage 5C does not yet write production generated files, the runtime workflow intentionally does not pretend that `services/<service>/generated/values.yaml` already exists.

The runtime workflow gates on Argo acceptance, repository/chart/values resolution, successful synchronization, expected resource creation, and representative live Deployment fields matching compiler-derived values. It records Application health only as diagnostic context. Requiring workload health here would couple the GitOps compiler proof to container runtime behavior, which is covered by the Stage 4 workload contract and later complete golden-path proof.

## Alternatives Considered

- Reuse the Stage 4 `golden-path` AppProject: rejected because generated self-service workloads need a distinct namespace boundary and should not broaden the demo project.
- Generate an AppProject per service: rejected because project policy is platform-owned and shared across v1alpha1 services.
- Use ApplicationSet immediately: rejected because discovery and controller-side generation are a separate lifecycle concern.
- Point generated Applications at service directories instead of the chart: rejected because Stage 4 already owns the workload implementation API.
- Use service-specific target revisions: rejected for this slice because deterministic committed artifacts should preserve the existing GitOps desired-state model.
