# Golden-Path Helm Chart

Stage 4 adds a reusable Helm application contract at `platform/helm-charts/golden-path`. The chart is intended for ordinary HTTP services that need predictable Kubernetes defaults, GitOps delivery, and clear review boundaries.

The chart is not a service generator, image build system, policy engine, observability stack, or environment promotion model. Those capabilities remain later-stage work.

## Version Boundary

The authoritative Helm validation tool contract is `platform/helm-charts/versions.env`.

- Helm: `v3.21.0`
- kubeconform: `v0.7.0`
- Kubernetes schema target for rendered manifests: `1.35.5`

Helm 3 is used because the Stage 3 Argo CD control plane renders Helm applications through Helm 3. The repository may detect newer local Helm clients, but Stage 4 validation expects the pinned Helm 3 release until the platform control plane intentionally changes.

## Chart Scope

The chart renders:

- Deployment
- Service
- ServiceAccount
- ConfigMap for non-secret configuration
- PodDisruptionBudget when enabled
- HorizontalPodAutoscaler when enabled
- NetworkPolicy when enabled
- Ingress when enabled

The chart does not render Kubernetes Secret resources. Secret integration is limited to references to existing Secrets through `existingSecret.envFrom` and `existingSecret.env`. Secret creation, external secret synchronization, and secret rotation are future platform concerns.

## Runtime Profile

The runtime demonstration profile is `platform/helm-charts/golden-path/tests/values/runtime-kind.yaml`. It deploys the Kubernetes `agnhost` `netexec` test server with an immutable image digest, two replicas, HTTP probes, resource requests and limits, restricted security contexts, a Service, a ConfigMap, a ServiceAccount, a PodDisruptionBudget, and scheduling spread guidance.

The feature-complete profile is `platform/helm-charts/golden-path/tests/values/feature-complete.yaml`. It renders optional HPA, NetworkPolicy, Ingress, and existing Secret references without creating any Secret.

The invalid profile is `platform/helm-charts/golden-path/tests/values/invalid-image.yaml`. It exists to prove schema rejection of floating `latest` tags.

## Static Validation

Run the repository baseline without a cluster:

```bash
make validate
```

Run Helm-specific static validation with the pinned Helm and kubeconform versions available on `PATH`:

```bash
make verify-helm-tools
make helm-lint
make helm-render
make helm-validate
```

`make helm-validate` performs strict Helm linting, rejects the invalid values fixture, renders the runtime and feature-complete profiles, validates rendered Kubernetes resources through kubeconform, and checks chart structure with repository assertions.

## GitOps Runtime Validation

Stage 4 deploys through Argo CD. It does not use `helm install` as the runtime proof.

Create and validate the local platform foundation:

```bash
make cluster-create
make gitops-install
make gitops-bootstrap
make gitops-validate
```

Bootstrap the golden-path application from the default tracked revision:

```bash
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
```

Bootstrap against a specific reviewed commit:

```bash
GOLDEN_PATH_TARGET_REVISION=<full-commit-sha> make golden-path-bootstrap
```

The revision may be `main` or a full lowercase 40-character commit SHA. CI uses the exact pull-request head SHA for both checkout and Argo CD target revision.

## Safe Removal

Remove only Stage 4 runtime state:

```bash
make golden-path-delete
```

The delete command removes the `golden-path-demo` Application, the `golden-path` AppProject, and the `golden-path-demo` namespace. It then verifies that the Stage 3 GitOps control plane and the Stage 2 Kind cluster remain healthy. It does not remove Argo CD, the `platform-bootstrap` Application, the Kind cluster, Docker resources, unrelated namespaces, local branches, or remote branches.

## Runtime Evidence

`make golden-path-validate` proves:

- Argo CD reports the Application as Healthy and Synced
- the Deployment rolls out successfully
- pods are Ready
- the runtime image is digest-pinned
- pod and container security contexts are restricted
- the Service selector matches the Deployment selector
- ready EndpointSlice endpoints exist
- the Service returns an HTTP health response
- expected ConfigMap data is present
- the PodDisruptionBudget exists

## Troubleshooting

If Helm validation fails locally, confirm that Helm `v3.21.0` and kubeconform `v0.7.0` are on `PATH`. The repository intentionally does not install arbitrary system-wide tooling.

If runtime validation refuses to continue because of the Kubernetes context, switch back to `kind-idp-local`. The scripts intentionally refuse to operate against any other cluster.

If Argo CD does not sync the application, inspect:

```bash
make golden-path-status
kubectl -n argocd describe application golden-path-demo --context kind-idp-local
kubectl -n golden-path-demo get pods --context kind-idp-local
```
