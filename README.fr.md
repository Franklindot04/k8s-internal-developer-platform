# Kubernetes Internal Developer Platform

[English](README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Ce dépôt est en cours de reconstruction en tant que projet de portfolio d'une Plateforme Interne de Développeur (IDP) Kubernetes avec une approche local-first. L'objectif est de démontrer une ingénierie de plateforme pratique grâce à des environnements Kubernetes reproductibles, une livraison GitOps, un golden path réutilisable avec Helm, un self-service pour les développeurs, des contrôles de la chaîne d'approvisionnement logicielle, une application des politiques, de l'observabilité, du CI/CD et une documentation opérationnelle.

## État Actuel

Le projet a franchi l'étape de publication de confiance à l'Étape 6D pour le fixture représentatif. L'Étape 1 a établi la baseline de récupération et d'ingénierie, l'Étape 2 a ajouté une base de cluster local réelle basée sur Kind, l'Étape 3 a ajouté le bootstrap d'Argo CD et la preuve de réconciliation, l'Étape 4 a ajouté un contrat de workload réutilisable avec Helm et une validation du runtime via GitOps, l'Étape 5 a ajouté la base du self-service pour les développeurs et l'Étape 6 dispose désormais d'une publication de confiance éprouvée en production sur la branche protégée `main` avec un handoff de digest faisant autorité.

La base Kubernetes locale est implémentée avec Kind. Argo CD est installé à partir d'un manifeste upstream épinglé et vérifié par checksum, puis utilisé pour réconcilier l'état minimal de bootstrap de la plateforme et le workload de démonstration du golden path. L'Étape 5 peut valider, planifier, générer et vérifier les artefacts de dépôt `PlatformService`. L'Étape 6 a défini l'architecture de la chaîne d'approvisionnement, le fixture de build représentatif, le chemin de preuve de PR non fiable et le chemin de publication OCI de confiance via un digest public faisant autorité. La signature, la provenance cryptographique ou l'attestation, les attestations jointes au registry, les politiques Kyverno, l'observabilité, la promotion entre environnements et les futurs workflows de livraison d'applications restent des capacités cibles pour les étapes ultérieures.

## Capacités Cibles

- Plateforme Kubernetes locale reproductible utilisant Kind
- Réconciliation GitOps avec Argo CD
- Empaquetage d'applications réutilisable de qualité production avec Helm
- Génération de services en self-service pour les développeurs
- Workflows de validation et CI/chaîne d'approvisionnement avec GitHub Actions
- Publication OCI de confiance, digests d'images immuables, SBOM, preuve de vulnérabilités et provenance future
- Application de politiques natives Kubernetes avec Kyverno
- Métriques, logs, tracing, alertes et conseils opérationnels SRE
- Architecture claire, ADRs, enregistrements de récupération et documentation du roadmap

## Résumé de l'Architecture

La plateforme prévue sépare le bootstrap d'infrastructure, les capacités de la plateforme, les workloads de référence, les outils pour développeurs et la documentation. Le parcours de démonstration local pourra être exécuté sans dépenses cloud obligatoires, tandis que l'architecture laisse place à un futur déploiement de référence cloud optionnel.

Consultez [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md) pour l'architecture cible et l'état actuel du dépôt. Consultez [docs/supply-chain-architecture.md](docs/supply-chain-architecture.md) pour les contrats de confiance, artefacts, preuves, publication et handoff de la chaîne d'approvisionnement de l'Étape 6.

Pour un parcours concis de revue du cœur de la plateforme implémentée, consultez [docs/runbooks/platform-walkthrough.md](docs/runbooks/platform-walkthrough.md).

## Structure du Dépôt

- `infra/` – bootstrap du cluster, configuration de bootstrap du control-plane Argo CD, infrastructure d'environnements future et bootstrap des politiques de la plateforme.
- `platform/` – état de bootstrap de la plateforme géré via GitOps, chart Helm golden path réutilisable et futurs add-ons et contrats partagés de la plateforme.
- `services/` – sources d'intention de service, artefacts de service générés et gérés par la plateforme et futurs workloads de référence.
- `tools/` – outils destinés aux développeurs, génération de services et outils de support du dépôt.
- `docs/` – architecture, ADRs, décisions de récupération, roadmap et documentation future pour développeurs et opérateurs.
- `.github/` – workflows de validation du dépôt et de preuve de la plateforme locale.
- `scripts/` – validation du dépôt, Kubernetes local, GitOps, chart Helm et scripts du cycle de vie du golden path.

Le contrat détaillé des répertoires est documenté dans [docs/repository/structure-contract.md](docs/repository/structure-contract.md).

## Roadmap

Le roadmap d'implémentation enregistre le cœur de la plateforme de référence local-first terminé et les domaines optionnels d'expansion future. Les travaux ultérieurs sur les politiques, l'observabilité, la promotion, la provenance et le portail font partie du périmètre futur et ne constituent pas un blocage pour l'examen du cœur actuel.

Consultez [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md).

## Validation

Le dépôt inclut une petite baseline de validation statique :

```bash
make help
make verify-tools
make validate
```

La validation vérifie la structure du dépôt, l'hygiène Markdown et les liens internes, la syntaxe YAML des fichiers existants, la syntaxe shell et le YAML des workflows GitHub Actions. Elle ne crée pas de cluster Kubernetes, n'installe pas Argo CD, ne déploie pas de workloads, ne publie pas d'artefacts et ne nécessite pas de credentials cloud.

## Kubernetes Local

L'Étape 2 fournit une base reproductible de Kubernetes local utilisant un cluster Kind nommé :

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

La plateforme locale utilise le nom de cluster `idp-local` et le contexte kubeconfig `kind-idp-local`. Consultez [docs/local-kubernetes.md](docs/local-kubernetes.md) pour les versions prises en charge, le comportement du cycle de vie, la validation et le dépannage.

## Control Plane GitOps

L'Étape 3 fournit un control plane Argo CD local reproductible et une ressource minimale de bootstrap gérée via Git :

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

Le bootstrap GitOps utilise le namespace `argocd`, réconcilie l'Application `platform-bootstrap` depuis `main` par défaut et prouve la correction du drift et la recréation des ressources gérées. Consultez [docs/gitops.md](docs/gitops.md).

## Chart Helm Golden Path

L'Étape 4 fournit un chart Helm réutilisable pour les services HTTP ordinaires :

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

Le chart est déployé via Argo CD, utilise un AppProject `golden-path` et une Application `golden-path-demo` dédiés et valide des paramètres par défaut sécurisés, notamment des images épinglées par digest, des probes, des ressources, des contextes de sécurité, le routage du Service, les données ConfigMap et la gestion des disruptions. Consultez [docs/golden-path.md](docs/golden-path.md).

## Contribuer

Les contributions utilisent des branches de courte durée et des pull requests vers `main`. Les branches historiques restent préservées pour l'attribution et la preuve de récupération ; elles ne doivent pas être utilisées directement comme base pour de nouveaux travaux d'implémentation.

Consultez [CONTRIBUTING.md](CONTRIBUTING.md).

## Récupération Historique

L'audit forensique a conclu que les branches historiques contiennent des concepts de conception utiles mais ne doivent pas être fusionnées en bloc. Les travaux futurs récupéreront ou réimplémenteront délibérément les concepts approuvés tout en préservant l'attribution des contributeurs.

Consultez [docs/recovery/historical-recovery.md](docs/recovery/historical-recovery.md).
