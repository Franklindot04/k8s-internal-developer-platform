# Helm Design Recovery

Stage 4 inspected the historical `feature/base-helm-structure` branch as evidence only. No files were merged, copied, or cherry-picked from that branch.

## Useful Concepts Reimplemented

- A reusable base chart concept
- Helm helper templates for names, labels, and selectors
- Deployment and Service as the core workload resources
- Optional probes, resources, disruption handling, network policy, ingress, and autoscaling
- A values schema and profile-style validation inputs
- Scripted chart validation

## Historical Defects Rejected

- Unsafe floating image tag defaults
- Secret templating from chart values
- Incomplete scripts that reported success without validating behavior
- Mismatched Deployment and Service selectors
- Undefined helper template references
- Metadata tied to non-project domains
- Unrestricted NetworkPolicy shapes
- Minimal schema coverage that did not protect core runtime contracts
- Unrelated generated service scaffolding before the chart contract existed

## Stage 4 Recovery Decision

The approved path is selective recovery by clean reimplementation. The new chart uses the existing Stage 1-3 repository structure, validates with pinned Helm and kubeconform versions, deploys through Argo CD, and keeps the historical branch preserved for attribution and audit evidence.

Service generation, application source templates, chart publishing, observability integration, and environment promotion were deliberately deferred.
