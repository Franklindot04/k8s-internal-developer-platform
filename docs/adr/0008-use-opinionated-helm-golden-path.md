# ADR 0008: Use an Opinionated Helm Golden Path

## Status

Accepted

## Context

The platform needs a reusable application deployment contract before service generation, policy enforcement, observability, and promotion workflows can be added. The historical Helm branch contained useful concepts, but it also mixed incomplete scaffolding with unsafe defaults and broken selectors. Stage 4 needs a clean implementation that can be validated independently and deployed through the existing GitOps control plane.

Argo CD `v3.4.2` renders Helm applications through Helm 3. Stage 4 therefore validates against Helm `v3.21.0` rather than introducing a Helm 4 runtime requirement before the control-plane renderer supports that assumption.

## Decision

Create an opinionated Helm chart at `platform/helm-charts/golden-path`.

The chart provides a constrained HTTP workload contract: Deployment, Service, ServiceAccount, ConfigMap, probes, resources, security contexts, PodDisruptionBudget, optional HorizontalPodAutoscaler, optional NetworkPolicy, optional Ingress, scheduling controls, labels, selectors, and a JSON values schema.

The chart does not template Kubernetes Secret resources. It supports only references to existing Secrets.

Runtime proof deploys the chart through Argo CD using a dedicated `golden-path` AppProject and `golden-path-demo` Application. The committed Application tracks `main`; CI renders an immutable commit SHA into a temporary Application manifest so the tested checkout and reconciled revision are the same.

## Consequences

Application workloads get secure and reliable defaults before later self-service tooling exists.

The chart is intentionally narrower than a general Helm starter kit. This keeps validation meaningful and makes the project completable by one maintainer.

Teams that need behavior outside the chart contract must either extend the chart through a reviewed platform change or wait for later-stage service generation and environment modeling.

Secret creation, ServiceMonitor integration, advanced rollout strategies, Gateway API, image building, supply-chain attestations, and generated services remain future-stage capabilities.
