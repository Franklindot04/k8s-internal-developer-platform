# Platform Architecture Overview

## Purpose

This repository is intended to become a Kubernetes Internal Developer Platform for demonstrating practical platform engineering. The platform should make common application delivery workflows repeatable, observable, secure, and reviewable.

The platform is local-first. A maintainer should be able to demonstrate the core platform on a workstation without mandatory cloud infrastructure. A future cloud reference deployment may be added, but cloud resources are not required for the primary demonstration path.

## Audience

The platform serves two groups:

- Application developers who need a supported path for creating, configuring, validating, and deploying services.
- Platform maintainers who own Kubernetes infrastructure, delivery standards, policies, observability, reliability practices, and documentation.

## Platform Goals

- Provide a reproducible local Kubernetes environment.
- Use Git as the source of truth for platform and application delivery.
- Standardize application packaging through a reusable Helm golden path.
- Offer developer self-service without hiding operational responsibilities.
- Enforce baseline security and reliability expectations through policy and validation.
- Make health, telemetry, and operational evidence visible.
- Keep each implementation stage reviewable and testable.

## Platform Boundaries

The platform will own cluster bootstrap, GitOps bootstrap, shared Kubernetes standards, the golden-path chart, platform validation, policy, observability integration, and reference workflows.

Application teams remain responsible for service behavior, application tests, service ownership metadata, runtime configuration choices, and responding to service-specific operational signals.

## Current Repository State

The current repository includes the recovery and engineering baseline, a reproducible local Kubernetes foundation using Kind, and a reproducible Argo CD GitOps control plane for local reconciliation. It contains documentation, governance files, validation scripts, directory contracts, Kind cluster configuration, local cluster lifecycle commands, Argo CD bootstrap configuration, and a minimal Git-managed platform bootstrap resource. It does not yet contain a Helm golden-path chart, Kyverno policy set, observability stack, service generator, environment promotion model, or application deployment workflow.

## Target Architecture

The target architecture has four conceptual layers:

- Repository control layer: branch strategy, pull requests, validation, ADRs, roadmap, and recovery controls.
- Platform control plane: Kind for local Kubernetes, Argo CD for GitOps reconciliation, Kyverno for policy enforcement, and observability components.
- Workload plane: namespaces, quotas, network boundaries, service accounts, Deployments, Services, ingress or Gateway integration, probes, resources, and telemetry.
- Developer experience layer: service templates, generator inputs, metadata, CI generation, Helm values, GitOps registration, and documentation output.

## Developer Responsibilities

Developers should use supported service templates, provide required metadata, write application tests, define service configuration, review generated output, and keep documentation accurate when behavior changes.

## Platform Team Responsibilities

The platform owner maintains cluster bootstrap, GitOps structure, Helm standards, repository validation, security policy, observability defaults, runbooks, upgrade guidance, and roadmap sequencing.

## Control Plane Concepts

Kind provides the local Kubernetes cluster. Argo CD reconciles Stage 3 platform bootstrap state from Git into the cluster. Kyverno will enforce Kubernetes-native policies in a later stage. GitHub Actions validates repository changes before merge.

Kind is implemented as the Stage 2 local Kubernetes foundation. Argo CD is implemented as the Stage 3 GitOps control plane using a pinned non-HA upstream manifest for local development. Kyverno and later platform components remain planned future-stage work.

## Workload Plane Concepts

Workloads will be deployed through standardized Kubernetes manifests rendered by Helm. Expected workload standards include labels, health probes, resource requests and limits, security contexts, service accounts, disruption handling, network policy, and telemetry integration.

## GitOps Operating Model

Git is the source of truth for Stage 3 platform bootstrap state. Platform configuration is reviewed through pull requests, merged into `main`, and reconciled into the local cluster by Argo CD. CI tests the exact commit under review by temporarily rendering the Argo CD Application target revision to the immutable commit SHA. Promotion between environments remains a later-stage concern and will be modeled through explicit Git changes rather than manual cluster mutation.

## Developer Golden Path

The future golden path will guide a developer from service creation through local validation, CI checks, GitOps registration, deployment, and observability. Stage 1 defines this direction only; the generator and deployment flow are later-stage work.

## Environment Model

The planned environment model includes local platform bootstrap plus development, staging, and production-style configuration boundaries. The project will demonstrate promotion and policy behavior locally first, with optional cloud portability later.

## Security Model

Security will be layered across repository validation, branch review, container and dependency checks, Kubernetes RBAC, Pod Security Standards, namespace isolation, network policy, secret handling, and Kyverno policy enforcement.

Current controls include repository validation, protected pull-request workflow, pinned local Kubernetes tooling, pinned and checksum-verified Argo CD installation, and a restricted Stage 3 AppProject. Kyverno policy enforcement remains planned future-stage work.

## Observability Model

The future observability model will include application and platform metrics, logs, traces, dashboards, alerts, service-level indicators, and runbooks. It will prioritize evidence that a service is healthy and operable, not only deployable.

## Software Delivery Model

GitHub Actions will provide repository validation during Stage 1. Later stages will add application CI, image builds, security scanning, SBOM generation, immutable image references, provenance considerations, and promotion controls.

## Non-Goals

- Do not require cloud infrastructure for the primary demonstration.
- Do not merge stale historical branches wholesale.
- Do not add platform components before their validation and operating model are defined.
- Do not document features as complete before they can be executed and verified.
- Do not increase repository size through empty directories or decorative files.
