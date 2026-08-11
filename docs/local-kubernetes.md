# Local Kubernetes Foundation

Stage 2 provides a deterministic local Kubernetes runtime foundation for this Internal Developer Platform. It creates and validates a named Kind cluster that later stages will use for GitOps, policy, observability, and golden-path workload demonstrations.

Stage 2 does not install Argo CD, Helm charts, Kyverno, observability components, service generators, application workloads, or cloud infrastructure.

## Supported Versions

The authoritative version contract is `infra/kubernetes/kind/versions.env`.

- Kind: `v0.32.0`
- Kubernetes node image: `kindest/node:v1.35.5` pinned by digest
- Kubernetes version: `v1.35.5`
- kubectl: client minor version `1.34`, `1.35`, or `1.36`
- Container runtime: Docker with a reachable daemon

Kind release notes for `v0.32.0` list the pinned Kubernetes `v1.35.5` node image digest. Kind release notes state that node images support amd64 and arm64 where upstream tooling supports those platforms. Kubernetes version skew policy supports kubectl within one minor version of the control plane.

## Architecture

Cluster name: `idp-local`

Expected kubeconfig context: `kind-idp-local`

Topology:

- 1 control-plane node
- 2 worker nodes

The configuration lives at `infra/kubernetes/kind/cluster.yaml`. It intentionally avoids ingress, port mappings, feature gates, GitOps bootstrap, policy engines, observability stacks, and application workloads. Those are later-stage concerns.

## Commands

Verify local tooling:

```bash
make verify-cluster-tools
```

Create the cluster:

```bash
make cluster-create
```

If `idp-local` already exists, creation leaves it in place and validates it instead of deleting or recreating it.

Inspect cluster status:

```bash
make cluster-status
```

Validate readiness:

```bash
make cluster-validate
```

Delete only the project cluster:

```bash
make cluster-delete
```

Deletion targets only `idp-local`. It does not remove unrelated Kind clusters, Docker containers, images, volumes, or kubeconfig entries beyond Kind's normal cleanup for this named cluster.

## Validation Behavior

Cluster validation checks:

- the expected Kind cluster exists
- the expected kubeconfig context exists
- the Kubernetes API is reachable
- all nodes become `Ready`
- exactly three nodes exist
- exactly one control-plane node exists
- exactly two worker nodes exist
- kube-system pods are ready
- the API server readiness endpoint responds

Validation uses bounded waits and returns a non-zero exit code on failure.

## Troubleshooting

If `make verify-cluster-tools` fails, install or correct the reported tool before creating the cluster. The project does not install local system tools for you.

If Docker is installed but unavailable, start Docker Desktop or the local Docker daemon and rerun verification.

If the Kind version does not match the version contract, install the supported Kind version or update the contract in a separate reviewed change.

If kubectl is outside the supported skew range, install a compatible kubectl client for Kubernetes `v1.35.5`.

If validation fails because the cluster is partially created or unhealthy, inspect with:

```bash
make cluster-status
kubectl get pods -A --context kind-idp-local
```

Then remove only the project cluster with:

```bash
make cluster-delete
```

## Relationship to Future Stages

This foundation gives later stages a reproducible Kubernetes runtime. Stage 3 will add GitOps control-plane work. Later stages will add the golden-path Helm chart, service generation, policy enforcement, observability, promotion, and SRE practices.
