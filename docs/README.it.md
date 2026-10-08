# Kubernetes Internal Developer Platform

[English](../README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Questo repository è in fase di ricostruzione come progetto portfolio di una Piattaforma Interna per Sviluppatori (IDP) Kubernetes con approccio local-first. L'obiettivo è dimostrare ingegneria di piattaforma pratica attraverso ambienti Kubernetes riproducibili, consegna GitOps, un golden path riutilizzabile con Helm, self-service per sviluppatori, controlli della catena di approvvigionamento software, applicazione di policy, osservabilità, CI/CD e documentazione operativa.

## Stato Attuale

Il progetto ha completato il traguardo di pubblicazione affidabile nella Fase 6D per il fixture rappresentativo. La Fase 1 ha stabilito la baseline di recupero e ingegneria, la Fase 2 ha aggiunto una base di cluster locale reale basata su Kind, la Fase 3 ha aggiunto il bootstrap di Argo CD e la prova di riconciliazione, la Fase 4 ha aggiunto un contratto di workload riutilizzabile con Helm e validazione del runtime tramite GitOps, la Fase 5 ha aggiunto la base del self-service per sviluppatori e la Fase 6 ora dispone di pubblicazione affidabile testata in produzione sul branch protetto `main` con handoff di digest autorevole.

La base Kubernetes locale è implementata con Kind. Argo CD viene installato da un manifesto upstream fissato e verificato tramite checksum, quindi utilizzato per riconciliare lo stato minimo di bootstrap della piattaforma e il workload di demo del golden path. La Fase 5 può validare, pianificare, generare e verificare artefatti del repository `PlatformService`. La Fase 6 ha definito l'architettura della catena di approvvigionamento, il fixture di build rappresentativo, il percorso di evidenza di PR non affidabile e il percorso di pubblicazione OCI affidabile tramite un digest pubblico autorevole. Firma, provenienza crittografica o attestazione, attestazioni allegate al registry, policy Kyverno, osservabilità, promozione tra ambienti e futuri workflow di consegna applicazioni rimangono capacità target per fasi successive.

## Capacità Target

- Piattaforma Kubernetes locale riproducibile utilizzando Kind
- Riconciliazione GitOps con Argo CD
- Pacchetto applicazioni riutilizzabile di qualità production con Helm
- Generazione di servizi self-service per sviluppatori
- Workflow di validazione e CI/catena di approvvigionamento con GitHub Actions
- Pubblicazione OCI affidabile, digest di immagini immutabili, SBOM, evidenza di vulnerabilità e provenienza futura
- Applicazione di policy native Kubernetes con Kyverno
- Metriche, log, tracing, alert e orientamento operativo SRE
- Architettura chiara, ADR, registri di recupero e documentazione del roadmap

## Riepilogo dell'Architettura

La piattaforma prevista separa bootstrap dell'infrastruttura, capacità della piattaforma, workload di riferimento, strumenti per sviluppatori e documentazione. Il percorso di dimostrazione locale potrà essere eseguito senza spese cloud obbligatorie, mentre l'architettura lascia spazio a un futuro deployment di riferimento cloud opzionale.

Consultare [docs/architecture/platform-overview.md](architecture/platform-overview.md) per l'architettura target e lo stato attuale del repository. Consultare [docs/supply-chain-architecture.md](supply-chain-architecture.md) per i contratti di trust, artefatti, evidenze, pubblicazione e handoff della catena di approvvigionamento della Fase 6.

Per un percorso conciso di revisione del nucleo della piattaforma implementata, consultare [docs/runbooks/platform-walkthrough.md](runbooks/platform-walkthrough.md).

## Struttura del Repository

- `infra/` – bootstrap del cluster, configurazione di bootstrap del control-plane Argo CD, infrastruttura di ambienti futura e bootstrap delle policy della piattaforma.
- `platform/` – stato di bootstrap della piattaforma gestito tramite GitOps, chart Helm golden path riutilizzabile e futuri add-on e contratti condivisi della piattaforma.
- `services/` – fonti di intent dei servizi, artefatti di servizio generati e gestiti dalla piattaforma e futuri workload di riferimento.
- `tools/` – strumenti rivolti agli sviluppatori, generazione di servizi e strumenti di supporto del repository.
- `docs/` – architettura, ADR, decisioni di recupero, roadmap e documentazione futura per sviluppatori e operatori.
- `.github/` – workflow di validazione del repository e di prova della piattaforma locale.
- `scripts/` – validazione del repository, Kubernetes locale, GitOps, chart Helm e script del ciclo di vita del golden path.

Il contratto dettagliato delle directory è documentato in [docs/repository/structure-contract.md](repository/structure-contract.md).

## Roadmap

Il roadmap di implementazione registra il nucleo completato della piattaforma di riferimento local-first e le aree opzionali di espansione futura. I lavori successivi su policy, osservabilità, promozione, provenienza e portale fanno parte dello scope futuro e non sono un blocco per la revisione del nucleo attuale.

Consultare [docs/roadmap/implementation-roadmap.md](roadmap/implementation-roadmap.md).

## Validazione

Il repository include una piccola baseline di validazione statica:

```bash
make help
make verify-tools
make validate
```

La validazione verifica la struttura del repository, l'igiene Markdown e i link interni, la sintassi YAML dei file esistenti, la sintassi shell e lo YAML dei workflow GitHub Actions. Non crea un cluster Kubernetes, non installa Argo CD, non esegue deploy di workload, non pubblica artefatti e non richiede credenziali cloud.

## Kubernetes Locale

La Fase 2 fornisce una base riproducibile di Kubernetes locale utilizzando un cluster Kind denominato:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

La piattaforma locale utilizza il nome del cluster `idp-local` e il contesto kubeconfig `kind-idp-local`. Consultare [docs/local-kubernetes.md](local-kubernetes.md) per le versioni supportate, il comportamento del ciclo di vita, la validazione e la risoluzione dei problemi.

## Control Plane GitOps

La Fase 3 fornisce un control plane Argo CD locale riproducibile e una risorsa minima di bootstrap gestita tramite Git:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

Il bootstrap GitOps utilizza il namespace `argocd`, riconcilia l'Application `platform-bootstrap` da `main` per impostazione predefinita e dimostra la correzione del drift e la ricreazione delle risorse gestite. Consultare [docs/gitops.md](gitops.md).

## Chart Helm Golden Path

La Fase 4 fornisce un chart Helm riutilizzabile per servizi HTTP ordinari:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

Il chart viene distribuito tramite Argo CD, utilizza un AppProject `golden-path` e un'Application `golden-path-demo` dedicati e valida impostazioni predefinite sicure, tra cui immagini fissate tramite digest, probe, risorse, security context, routing del Service, dati ConfigMap e gestione delle disruption. Consultare [docs/golden-path.md](golden-path.md).

## Contribuire

I contributi utilizzano branch di breve durata e pull request verso `main`. I branch storici rimangono preservati per attribuzione ed evidenza di recupero; non devono essere utilizzati direttamente come base per nuovi lavori di implementazione.

Consultare [CONTRIBUTING.md](../CONTRIBUTING.md).

## Recupero Storico

L'audit forense ha concluso che i branch storici contengono concetti di design utili ma non devono essere uniti in blocco. I lavori futuri recupereranno o reimpiegheranno deliberatamente i concetti approvati, preservando allo stesso tempo l'attribuzione dei contributori.

Consultare [docs/recovery/historical-recovery.md](recovery/historical-recovery.md).
