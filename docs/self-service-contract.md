# Developer Self-Service Contract

Stage 5 introduces a developer-owned service intent contract for the Kubernetes Internal Developer Platform. The contract is now validated and can be compiled into deterministic Stage 4-compatible Helm values for review. GitOps registration, repository write behavior, and any future portal or API remain later work.

## Purpose

The self-service flow is:

```text
developer intent
-> strict versioned validation
-> deterministic generated configuration
-> Stage 4 golden-path Helm chart
-> GitOps-ready desired state
-> Argo CD lifecycle
```

Stage 5A implemented the versioned contract and validation foundation. Stage 5B adds deterministic read-only planning from `PlatformService` intent to golden-path Helm values. It does not generate files in the repository, create Argo CD Applications, Kubernetes workloads, CI pipelines, or application source code.

## Developer Persona

The normal developer is onboarding an ordinary HTTP service. They should provide service identity, ownership, image digest, runtime port, health path, resource intent, availability intent, non-secret configuration, and existing Secret references when needed.

They should not need to understand Deployment selectors, PodDisruptionBudget syntax, security contexts, Argo CD internals, Helm templates, or Kubernetes API versions.

## Source Of Truth

The handwritten source of truth is a service specification file using:

```yaml
apiVersion: idp/v1alpha1
kind: PlatformService
```

Generated files in later Stage 5 slices will be derived from this contract. Planned Helm values and future generated Argo CD Application files must not become competing sources of truth.

## Contract Identity

`apiVersion: idp/v1alpha1` identifies a repository-owned file contract. It is not a Kubernetes CRD API group.

`kind: PlatformService` intentionally avoids `kind: Service` because this file is not a Kubernetes core Service object.

## Required Shape

```yaml
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: inventory-api
  owner: platform-team
spec:
  image:
    repository: registry.test/platform/inventory-api
    digest: sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  runtime:
    port: 8080
    healthPath: /healthz
  resources:
    profile: small
  availability:
    profile: single
```

Unknown fields are rejected. This keeps v1alpha1 explicit and prevents accidental raw Kubernetes, Helm, or GitOps passthrough.

## Metadata

Required fields:

- `metadata.name`: lowercase DNS-safe service slug, maximum 48 characters.
- `metadata.owner`: team or owner slug.

Optional field:

- `metadata.description`: short service description.

The contract does not require personal email addresses, cost centers, service-catalog IDs, or speculative enterprise metadata.

## Image

Required fields:

- `spec.image.repository`
- `spec.image.digest`

The digest is mandatory and must be a lowercase SHA-256 digest:

```text
sha256:<64 lowercase hexadecimal characters>
```

The repository field identifies only the image repository. It must not include a URL scheme, embedded digest, embedded tag, whitespace, empty path segment, or trailing slash. Registry hosts may include a port.

Tag-only images are not accepted in v1alpha1. `latest` is not accepted. Stage 6 may later automate image production and digest updates, but Stage 5A keeps the service contract immutable.

## Runtime

Required fields:

- `spec.runtime.port`: application container port from `1024` through `65535`.
- `spec.runtime.healthPath`: absolute HTTP path beginning with `/`.

The health path must be a path only, not a URL, host, command, or probe script.

## Resources

Required field:

- `spec.resources.profile`

Allowed profiles:

- `small`
- `medium`
- `large`

Concrete CPU and memory mappings are platform-owned profile policy, not developer-authored raw resources.

Current demo/default operating profiles:

| Profile | CPU request | Memory request | CPU limit | Memory limit |
| --- | ---: | ---: | ---: | ---: |
| `small` | `50m` | `64Mi` | `250m` | `128Mi` |
| `medium` | `100m` | `128Mi` | `500m` | `256Mi` |
| `large` | `250m` | `256Mi` | `1000m` | `512Mi` |

These values are intentionally realistic for local Kind validation and ordinary demo workloads. They are not universal production sizing recommendations. Later contract versions may evolve profile semantics through controlled compatibility changes.

## Availability

Required field:

- `spec.availability.profile`

Allowed profiles:

- `single`
- `standard`

`single` maps to one replica, PDB disabled, and HPA disabled.

`standard` maps to two replicas, PDB enabled with `minAvailable: 1`, and HPA disabled.

Autoscaling is not exposed in v1alpha1 because the current platform does not install Metrics Server and does not prove HPA operation end to end.

## Configuration

Optional field:

```yaml
spec:
  config:
    LOG_LEVEL: info
```

Configuration is for non-secret string values only. Keys must be uppercase environment-style identifiers. The `PLATFORM_` prefix is reserved for platform-owned configuration.

Nested YAML, arbitrary templates, and executable expressions are not supported.

## Secret References

Optional field:

```yaml
spec:
  secrets:
    envFrom:
      - application-runtime
```

v1alpha1 exposes only references to existing Kubernetes Secrets through the narrow `envFrom` model supported by the Stage 4 chart. Raw secret values are forbidden. The contract must never contain credential values, generated Secret objects, secret-bearing `.env` files, or Secret templates.

## Deliberately Unsupported In V1Alpha1

The following are not developer-facing fields in v1alpha1:

- external exposure
- Ingress
- raw NetworkPolicy
- autoscaling
- raw HPA settings
- raw PDB settings
- node selectors
- affinity
- tolerations
- topology spread
- ServiceAccount annotations
- imagePullSecrets
- extra volumes
- raw Helm values
- raw Kubernetes objects
- arbitrary annotations
- arbitrary labels
- arbitrary commands or args

Some of these are technically supported by the Stage 4 chart. They are not part of normal Stage 5 self-service because the platform contract should reduce cognitive load.

## YAML Safety

Validation uses safe YAML loading and rejects duplicate mapping keys, multiple YAML documents, aliases, merge keys, and unsupported custom tags. v1alpha1 avoids YAML features that make developer intent ambiguous.

## Stage 4 Relationship

Stage 4 remains the Kubernetes implementation layer. Stage 5B maps `PlatformService` intent to the existing golden-path chart values. Developers do not author Deployment, Service, PodDisruptionBudget, securityContext, or Helm template details.

Mapped fields:

- `metadata.name` -> Stage 4 `fullnameOverride`
- `spec.image.repository` and `spec.image.digest` -> Stage 4 structured image fields
- `spec.runtime.port` -> Stage 4 `containerPort.port`
- `spec.runtime.healthPath` -> Stage 4 startup, readiness, and liveness HTTP paths
- `spec.resources.profile` -> platform-owned resource profile policy
- `spec.availability.profile` -> platform-owned replica/PDB/HPA policy
- `spec.config` -> Stage 4 non-secret ConfigMap data when present
- `spec.secrets.envFrom` -> Stage 4 existing Secret `envFrom` references

Intentionally unmapped fields:

- `metadata.owner`
- `metadata.description`

Stage 4 does not currently expose a narrow, platform-controlled metadata label interface for these fields. They remain useful source intent for later GitOps, catalog, and operational workflows.

The lower bound aligns developer intent with the current hardened golden-path runtime contract. This is a platform contract decision, not a statement that Kubernetes universally forbids lower container ports.

## Read-Only Planning

Preview deterministic values:

```bash
platformctl service plan services/<service>/service.yaml
```

`plan` validates the contract, normalizes intent, resolves platform profiles, renders deterministic Helm values, and prints the future output path:

```text
services/<service>/generated/values.yaml
```

The command is read-only. It does not create `services/`, service directories, `generated/`, values files, metadata files, temporary repository files, Argo CD Applications, AppProjects, or GitOps registrations.

## GitOps Relationship

This slice does not create Argo CD Applications or modify AppProjects. Later Stage 5 slices are expected to derive:

```text
services/<service>/generated/values.yaml
services/<service>/generated/application.yaml
```

from the handwritten service contract.

The generated Application will initially be a GitOps-ready artifact, not automatically discovered by an app-of-apps mechanism. Stage 5B does not create that Application. Stage 5 must not broaden the existing Stage 3 or Stage 4 AppProjects. A future shared service AppProject should be platform-owned, not generated per service.

The expected namespace convention for later slices is `svc-<service-name>`, subject to implementation validation.

## Argo CD Value File Constraint

Future Application generation will use the Stage 4 chart in the same repository and a service-specific generated values file. Value file paths must be validated against the Stage 4 chart and repository model, generated paths must stay inside the repository, and exact Argo CD value-file behavior must receive integration proof before Stage 5 is complete.

## Future Portal Compatibility

A future CLI, API, portal, or service catalog can use the same `PlatformService` contract. User interfaces should sit above the contract rather than redefining it.

## Historical Generator Relationship

The historical `feature/service-template-generator` branch informed the redesign, but it is forensic evidence only. Stage 5 does not merge, cherry-pick, copy wholesale, rewrite, or delete that branch.
