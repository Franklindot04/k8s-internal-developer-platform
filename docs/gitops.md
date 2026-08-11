# GitOps Control Plane

Stage 3 establishes the local GitOps control plane for the Kubernetes Internal Developer Platform. It installs Argo CD into the Stage 2 Kind cluster and proves that platform state can be reconciled from Git, corrected after drift, recreated after deletion, removed safely, and installed again.

Stage 3 does not implement the golden-path Helm chart, Kyverno, observability, service generation, environment promotion, application delivery pipelines, or cloud Kubernetes infrastructure.

Stage 4 adds a separate golden-path AppProject and Application for the demo workload. The Stage 3 `platform-bootstrap` Application remains intentionally small and independent.

## Version and Installation Boundary

The authoritative Argo CD version contract is `infra/gitops/argocd/versions.env`.

- Argo CD: `v3.4.2`
- Namespace: `argocd`
- Install model: official non-HA manifest at `manifests/install.yaml`
- Manifest integrity: SHA-256 checksum recorded in the version contract

The local Kind platform uses the official non-HA Argo CD installation because Stage 3 targets a single local demonstration cluster. This keeps the local resource footprint reasonable and avoids pretending that multiple local replicas model real production availability zones or failure domains. Production or cloud high availability remains a later architectural concern.

The Argo CD controller cannot reconcile itself before it exists. For that reason, Stage 3 uses a controlled bootstrap boundary:

- the local script creates the `argocd` namespace
- the script downloads the exact versioned upstream install manifest
- the script verifies its SHA-256 checksum before applying it
- the script applies the manifest with the upstream server-side apply semantics
- downstream platform bootstrap state is managed declaratively through Argo CD

## Bootstrap Scope

Stage 3 creates one Argo CD `AppProject` and one `Application`.

- AppProject: `platform-bootstrap`
- Application: `platform-bootstrap`
- Repository source: `https://github.com/Franklindot04/k8s-internal-developer-platform.git`
- Committed/default target revision: `main`
- Application path: `platform/gitops/bootstrap`
- Destination namespace: `platform-system`

The Git-managed bootstrap state is intentionally small:

- namespace `platform-system`
- ConfigMap `platform-bootstrap-metadata`

The ConfigMap is non-secret metadata used only to prove GitOps reconciliation, drift correction, and managed-resource recreation. It is not an application workload.

## Least Privilege

The AppProject restricts sources to this repository only. It restricts destinations to the in-cluster Kubernetes API and the `platform-system` namespace. Cluster-scoped permissions are limited to `Namespace`, which is required because the bootstrap path owns the `platform-system` namespace. Namespaced permissions are limited to `ConfigMap`.

The Argo CD API server is not exposed externally by Stage 3. The workflow and scripts do not print the initial admin password, secrets, tokens, or Kubernetes Secret contents.

## CI Revision Strategy

The committed Application manifest targets `main` so the merged repository remains the durable source of truth.

Before merge, CI must test the exact commit under review. The GitOps workflow derives one immutable test revision: pull-request runs use the PR head commit SHA, while manual `workflow_dispatch` runs use the triggering workflow commit SHA. The workflow checks out that same revision and passes it to `gitops-bootstrap` through `GITOPS_TARGET_REVISION`. The script validates the revision as either `main` or a full lowercase 40-character commit SHA, renders a temporary Application manifest, applies it, and leaves tracked files unchanged.

This avoids a permanent feature-branch target, floating `HEAD`, force-push dependency, or second long-lived CI-only configuration.

## Commands

Install only the Argo CD control plane:

```bash
make gitops-install
```

Bootstrap the AppProject/Application with the default `main` revision:

```bash
make gitops-bootstrap
```

Bootstrap against an immutable commit for CI or review:

```bash
GITOPS_TARGET_REVISION=<full-commit-sha> make gitops-bootstrap
```

Inspect control-plane, Application, and managed-resource status:

```bash
make gitops-status
```

Validate the control plane and synchronized bootstrap state:

```bash
make gitops-validate
```

Prove drift correction and managed ConfigMap recreation:

```bash
make gitops-test-reconciliation
```

Remove only Stage 3 GitOps state:

```bash
make gitops-delete
```

`make gitops-delete` removes the Stage 3 Application, AppProject, `platform-system` namespace, and `argocd` namespace. It does not delete the Kind cluster, unrelated namespaces, Docker resources, other Git repositories, or historical branches. After removal it verifies that the underlying `idp-local` cluster remains reachable and healthy.

## Reconciliation Proof

The reconciliation test modifies the managed ConfigMap directly through Kubernetes, then waits for Argo CD to restore the Git-declared value. It then deletes the ConfigMap and waits for Argo CD to recreate it with the expected content.

The script does not repair the resource itself. Argo CD must perform the restoration for the test to pass.

## Troubleshooting

If a GitOps command fails with an unexpected-context error, switch back to `kind-idp-local` before retrying. The scripts intentionally refuse to operate against any other Kubernetes context.

If installation fails with a checksum mismatch, do not bypass the check. Verify the official upstream release and update the version contract in a reviewed change only if the approved version or manifest has intentionally changed.

If the Application does not become healthy and synchronized, inspect:

```bash
make gitops-status
kubectl -n argocd describe application platform-bootstrap --context kind-idp-local
kubectl -n argocd get pods --context kind-idp-local
```

If deletion is interrupted, rerun:

```bash
make gitops-delete
```

The command is designed to handle already-absent Stage 3 resources predictably.
