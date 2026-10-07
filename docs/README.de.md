# Kubernetes Internal Developer Platform

[English](../README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Dieses Repository wird zu einem lokal-first Kubernetes Internal Developer Platform (IDP) Portfolio-Projekt umgebaut. Das Ziel ist es, praktische Plattform-Engineering durch reproduzierbare Kubernetes-Umgebungen, GitOps-Delivery, einen wiederverwendbaren Helm-Golden-Path, Entwickler-Self-Service, Software-Supply-Chain-Kontrollen, Policy-Durchsetzung, Observability, CI/CD und operative Dokumentation zu demonstrieren.

## Aktueller Status

Das Projekt hat den Meilenstein der vertrauenswürdigen Veröffentlichung in Stufe 6D für das repräsentative Fixture abgeschlossen. Stufe 1 etablierte die Recovery- und Engineering-Baseline, Stufe 2 fügte eine echte Kind-basierte lokale Cluster-Grundlage hinzu, Stufe 3 fügte Argo CD-Bootstrap und Reconciliation-Nachweis hinzu, Stufe 4 fügte einen wiederverwendbaren Helm-Workload-Contract mit GitOps-Runtime-Validierung hinzu, Stufe 5 fügte die Developer-Self-Service-Grundlage hinzu und Stufe 6 verfügt nun über eine live-getestete, geschützte `main`-Vertrauensveröffentlichung mit autoritativem Digest-Handoff.

Die lokale Kubernetes-Grundlage ist mit Kind implementiert. Argo CD wird aus einem gepinnten und checksummen-verifizierten Upstream-Manifest installiert und anschließend verwendet, um den minimalen Plattform-Bootstrap-Zustand und die Golden-Path-Demo-Workload zu reconcilieren. Stufe 5 kann `PlatformService`-Repository-Artefakte validieren, planen, generieren und verifizieren. Stufe 6 hat die Supply-Chain-Architektur, das repräsentative Build-Fixture, den unvertrauenswürdigen PR-Evidence-Pfad und den vertrauenswürdigen OCI-Veröffentlichungspfad durch einen öffentlichen autoritativen Digest definiert. Signierung, kryptografische Provenance oder Attestation, Registry-angehängte Attestationen, Kyverno-Policies, Observability, Environment-Promotion und spätere Application-Delivery-Workflows bleiben Zielkapazitäten für spätere Stufen.

## Zielkapazitäten

- Reproduzierbare lokale Kubernetes-Plattform mit Kind
- GitOps-Reconciliation mit Argo CD
- Produktionsreife wiederverwendbare Anwendungspaketierung mit Helm
- Entwickler-Self-Service-Service-Generierung
- GitHub Actions-Validierungs- und CI/Supply-Chain-Workflows
- Vertrauenswürdige OCI-Veröffentlichung, unveränderliche Image-Digests, SBOM, Vulnerability-Evidence und zukünftige Provenance
- Kubernetes-native Policy-Durchsetzung mit Kyverno
- Metriken, Logs, Tracing, Alerts und SRE-Betriebsanleitung
- Klare Architektur, ADRs, Recovery-Aufzeichnungen und Roadmap-Dokumentation

## Architekturzusammenfassung

Die geplante Plattform trennt Infrastruktur-Bootstrap, Plattformkapazitäten, Referenz-Workloads, Entwickler-Tooling und Dokumentation. Der lokale Demonstrationspfad wird ohne obligatorische Cloud-Ausgaben ausführbar sein, während die Architektur Raum für eine zukünftige optionale Cloud-Referenzimplementierung lässt.

Siehe [docs/architecture/platform-overview.md](architecture/platform-overview.md) für die Zielarchitektur und den aktuellen Repository-Status. Siehe [docs/supply-chain-architecture.md](supply-chain-architecture.md) für die Stage-6-Supply-Chain-Trust-, Artefakt-, Evidence-, Publikations- und Handoff-Contracts.

Für einen prägnanten Reviewer-Pfad durch den implementierten Plattformkern siehe [docs/runbooks/platform-walkthrough.md](runbooks/platform-walkthrough.md).

## Repository-Struktur

- `infra/` – Cluster-Bootstrap, Argo CD-Control-Plane-Bootstrap-Konfiguration, zukünftige Environment-Infrastruktur und Plattform-Policy-Bootstrap.
- `platform/` – GitOps-verwalteter Plattform-Bootstrap-Zustand, wiederverwendbarer Helm-Golden-Path-Chart und zukünftige Plattform-Add-Ons und gemeinsame Contracts.
- `services/` – Service-Intent-Quellen, plattformverwaltete generierte Service-Artefakte und zukünftige Referenz-Workloads.
- `tools/` – Entwicklerorientiertes Tooling, Service-Generierung und Repository-Support-Tooling.
- `docs/` – Architektur, ADRs, Recovery-Entscheidungen, Roadmap und spätere Entwickler/Operator-Dokumentation.
- `.github/` – Repository-Validierungs- und lokale Plattform-Nachweis-Workflows.
- `scripts/` – Repository-Validierung, lokales Kubernetes, GitOps, Helm-Chart und Golden-Path-Lifecycle-Skripte.

Der detaillierte Directory-Contract ist in [docs/repository/structure-contract.md](repository/structure-contract.md) dokumentiert.

## Roadmap

Die Implementierungs-Roadmap dokumentiert den abgeschlossenen lokal-first Referenzplattform-Kern und optionale zukünftige Erweiterungsbereiche. Spätere Arbeiten zu Policy, Observability, Promotion, Provenance und Portal sind zukünftiger Scope und kein Blocker für die Überprüfung des aktuellen Kerns.

Siehe [docs/roadmap/implementation-roadmap.md](roadmap/implementation-roadmap.md).

## Validierung

Das Repository enthält eine kleine statische Validierungs-Baseline:

```bash
make help
make verify-tools
make validate
```

Die Validierung prüft Repository-Struktur, Markdown-Hygiene und interne Links, YAML-Syntax für vorhandene Dateien, Shell-Syntax und GitHub Actions-Workflow-YAML. Sie erstellt keinen Kubernetes-Cluster, installiert kein Argo CD, deployt keine Workloads, veröffentlicht keine Artefakte und benötigt keine Cloud-Credentials.

## Lokales Kubernetes

Stufe 2 bietet eine reproduzierbare lokale Kubernetes-Grundlage mit einem benannten Kind-Cluster:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

Die lokale Plattform verwendet den Cluster-Namen `idp-local` und den Kubeconfig-Kontext `kind-idp-local`. Siehe [docs/local-kubernetes.md](local-kubernetes.md) für unterstützte Versionen, Lifecycle-Verhalten, Validierung und Troubleshooting.

## GitOps-Control-Plane

Stufe 3 bietet ein reproduzierbares lokales Argo CD-Control-Plane und eine minimale Git-verwaltete Bootstrap-Ressource:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

Das GitOps-Bootstrap verwendet den Namespace `argocd`, reconciliert die `platform-bootstrap`-Application standardmäßig von `main` und beweist Drift-Korrektur sowie Managed-Resource-Rekreation. Siehe [docs/gitops.md](gitops.md).

## Golden-Path-Helm-Chart

Stufe 4 bietet einen wiederverwendbaren Helm-Chart für gewöhnliche HTTP-Services:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

Der Chart wird über Argo CD deployed, verwendet ein dediziertes `golden-path`-AppProject und eine `golden-path-demo`-Application und validiert sichere Defaults einschließlich Digest-gepinnter Images, Probes, Resources, Security-Contexts, Service-Routing, ConfigMap-Daten und Disruption-Handling. Siehe [docs/golden-path.md](golden-path.md).

## Contributing

Beiträge verwenden kurzlebige Branches und Pull Requests in `main`. Historische Branches bleiben für Attribution und Recovery-Evidence erhalten; sie sollten nicht direkt als Basis für neue Implementierungsarbeiten verwendet werden.

Siehe [CONTRIBUTING.md](../CONTRIBUTING.md).

## Historical Recovery

Das forensische Audit kam zu dem Schluss, dass historische Branches nützliche Designkonzepte enthalten, aber nicht pauschal gemergt werden sollten. Zukünftige Arbeiten werden genehmigte Konzepte gezielt wiederherstellen oder neu implementieren und dabei die Contributor-Attribution bewahren.

Siehe [docs/recovery/historical-recovery.md](recovery/historical-recovery.md).
