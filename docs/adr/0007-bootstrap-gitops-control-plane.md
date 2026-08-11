# ADR 0007: Bootstrap GitOps Control Plane Before Git Reconciliation

## Status

Approved for Stage 3 implementation.

## Context

Argo CD is the selected GitOps engine, but the Argo CD controller must exist in the cluster before it can reconcile `Application` resources from Git. This creates a bootstrap boundary that should be explicit rather than hidden.

Stage 3 targets the local Kind platform. It needs a reproducible control plane, a defensible integrity check for the upstream install manifest, and a small Git-managed resource that proves reconciliation without introducing application workloads or later-stage platform components.

## Decision

Install the Argo CD control plane outside Git reconciliation using the official versioned non-HA upstream manifest, pinned to Argo CD `v3.4.2` and verified by SHA-256 before application.

After the controller is ready, create an Argo CD `AppProject` and `Application` that reconcile the repository path `platform/gitops/bootstrap` into the local cluster. The committed Application targets `main`. CI temporarily renders the same Application against the immutable commit under test.

Argo CD self-management is deferred. Stage 3 manages downstream platform bootstrap state through Argo CD, while the initial controller installation remains a controlled imperative step.

## Rationale

The controller cannot apply itself before it is running. A small imperative bootstrap step is therefore honest and operationally clear. Pinning the upstream manifest by version and checksum gives the project reproducibility without vendoring a large third-party manifest.

The downstream bootstrap path demonstrates the core GitOps behavior the project needs: declarative state, automated sync, pruning, self-healing, drift correction, and managed-resource recreation.

## Consequences

The bootstrap script must protect against accidental cluster targeting, verify the Kubernetes API and Kind topology, avoid logging secrets, and fail clearly when the remote manifest integrity check fails.

The AppProject must remain narrow enough to be understandable. Stage 3 allows only this repository as a source, only the in-cluster `platform-system` destination, only the cluster-scoped `Namespace` kind, and only namespaced `ConfigMap` resources.

Future stages may revisit Argo CD self-management, ApplicationSets, multi-environment registration, production HA, and broader platform component reconciliation when there is a real need.

## Alternatives Considered

- Vendor the full upstream Argo CD manifest: improves offline reproducibility but adds a large third-party manifest to the repository and increases maintenance noise.
- Use a floating upstream URL: simpler, but it breaks reproducibility and integrity control.
- Install the HA manifest locally: exercises more resources, but it does not model real production failure domains on one Kind cluster.
- Manage Argo CD with Argo CD immediately: attractive eventually, but it obscures the initial bootstrap paradox and adds unnecessary complexity for Stage 3.
