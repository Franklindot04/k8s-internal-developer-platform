# Kubernetes Internal Developer Platform

[English](README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Este repositório está sendo reconstruído como um projeto de portfólio de uma Plataforma Interna de Desenvolvedor (IDP) Kubernetes com abordagem local-first. O objetivo é demonstrar engenharia de plataforma prática por meio de ambientes Kubernetes reproduzíveis, entrega GitOps, um golden path reutilizável com Helm, autoatendimento para desenvolvedores, controles de cadeia de suprimentos de software, aplicação de políticas, observabilidade, CI/CD e documentação operacional.

## Status Atual

O projeto concluiu o marco de publicação confiável na Etapa 6D para o fixture representativo. A Etapa 1 estabeleceu a baseline de recuperação e engenharia, a Etapa 2 adicionou uma base de cluster local real baseada em Kind, a Etapa 3 adicionou bootstrap do Argo CD e prova de reconciliação, a Etapa 4 adicionou um contrato de workload reutilizável com Helm e validação de runtime via GitOps, a Etapa 5 adicionou a base de autoatendimento para desenvolvedores e a Etapa 6 agora possui publicação confiável testada em produção na branch protegida `main` com handoff de digest autorizado.

A base local do Kubernetes é implementada com Kind. O Argo CD é instalado a partir de um manifesto upstream fixado e verificado por checksum, e depois usado para reconciliar o estado mínimo de bootstrap da plataforma e o workload de demonstração do golden path. A Etapa 5 pode validar, planejar, gerar e verificar artefatos de repositório `PlatformService`. A Etapa 6 definiu a arquitetura da cadeia de suprimentos, o fixture de build representativo, o caminho de evidência de PR não confiável e o caminho de publicação OCI confiável por meio de um digest público autorizado. Assinatura, proveniência criptográfica ou atestação, atestações anexadas ao registry, políticas do Kyverno, observabilidade, promoção entre ambientes e fluxos de entrega de aplicativos futuros permanecem como capacidades alvo para etapas posteriores.

## Capacidades Alvo

- Plataforma Kubernetes local reproduzível usando Kind
- Reconciliação GitOps com Argo CD
- Empacotamento de aplicações reutilizável com qualidade de produção usando Helm
- Geração de serviços por autoatendimento para desenvolvedores
- Fluxos de validação e CI/cadeia de suprimentos com GitHub Actions
- Publicação OCI confiável, digests de imagem imutáveis, SBOM, evidência de vulnerabilidades e proveniência futura
- Aplicação de políticas nativas do Kubernetes com Kyverno
- Métricas, logs, tracing, alertas e orientação operacional de SRE
- Arquitetura clara, ADRs, registros de recuperação e documentação do roadmap

## Resumo da Arquitetura

A plataforma pretendida separa bootstrap de infraestrutura, capacidades da plataforma, workloads de referência, ferramentas para desenvolvedores e documentação. O caminho de demonstração local poderá ser executado sem gastos obrigatórios em nuvem, enquanto a arquitetura deixa espaço para uma futura implementação de referência opcional em nuvem.

Consulte [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md) para a arquitetura alvo e o estado atual do repositório. Consulte [docs/supply-chain-architecture.md](docs/supply-chain-architecture.md) para os contratos de confiança, artefatos, evidências, publicação e handoff da cadeia de suprimentos da Etapa 6.

Para um caminho conciso de revisão pelo núcleo da plataforma implementada, consulte [docs/runbooks/platform-walkthrough.md](docs/runbooks/platform-walkthrough.md).

## Estrutura do Repositório

- `infra/` – bootstrap do cluster, configuração de bootstrap do control-plane do Argo CD, infraestrutura de ambientes futura e bootstrap de políticas da plataforma.
- `platform/` – estado de bootstrap da plataforma gerenciado via GitOps, chart Helm golden path reutilizável e futuros add-ons e contratos compartilhados da plataforma.
- `services/` – fontes de intenção de serviço, artefatos de serviço gerados e gerenciados pela plataforma e futuros workloads de referência.
- `tools/` – ferramentas voltadas para desenvolvedores, geração de serviços e ferramentas de suporte do repositório.
- `docs/` – arquitetura, ADRs, decisões de recuperação, roadmap e documentação futura para desenvolvedores e operadores.
- `.github/` – fluxos de validação do repositório e de prova da plataforma local.
- `scripts/` – validação do repositório, Kubernetes local, GitOps, chart Helm e scripts do ciclo de vida do golden path.

O contrato detalhado de diretórios está documentado em [docs/repository/structure-contract.md](docs/repository/structure-contract.md).

## Roadmap

O roadmap de implementação registra o núcleo da plataforma de referência local-first concluído e áreas opcionais de expansão futura. Trabalhos futuros em políticas, observabilidade, promoção, proveniência e portal fazem parte do escopo futuro e não são um bloqueador para revisar o núcleo atual.

Consulte [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md).

## Validação

O repositório inclui uma pequena baseline de validação estática:

```bash
make help
make verify-tools
make validate
```

A validação verifica a estrutura do repositório, higiene de Markdown e links internos, sintaxe YAML para arquivos existentes, sintaxe de shell e YAML de fluxos do GitHub Actions. Ela não cria um cluster Kubernetes, não instala o Argo CD, não faz deploy de workloads, não publica artefatos e não requer credenciais de nuvem.

## Kubernetes Local

A Etapa 2 fornece uma base reproduzível de Kubernetes local usando um cluster Kind nomeado:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

A plataforma local usa o nome do cluster `idp-local` e o contexto kubeconfig `kind-idp-local`. Consulte [docs/local-kubernetes.md](docs/local-kubernetes.md) para versões suportadas, comportamento do ciclo de vida, validação e solução de problemas.

## Control Plane GitOps

A Etapa 3 fornece um control plane Argo CD local reproduzível e um recurso mínimo de bootstrap gerenciado via Git:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

O bootstrap GitOps usa o namespace `argocd`, reconcilia o Application `platform-bootstrap` a partir de `main` por padrão e prova correção de drift e recriação de recursos gerenciados. Consulte [docs/gitops.md](docs/gitops.md).

## Chart Helm Golden Path

A Etapa 4 fornece um chart Helm reutilizável para serviços HTTP comuns:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

O chart é implantado via Argo CD, usa um AppProject `golden-path` e um Application `golden-path-demo` dedicados e valida padrões seguros, incluindo imagens fixadas por digest, probes, recursos, contextos de segurança, roteamento do Service, dados do ConfigMap e tratamento de disrupção. Consulte [docs/golden-path.md](docs/golden-path.md).

## Contribuindo

Contribuições usam branches de curta duração e pull requests para `main`. Branches históricos permanecem preservados para atribuição e evidência de recuperação; eles não devem ser usados diretamente como base para novos trabalhos de implementação.

Consulte [CONTRIBUTING.md](CONTRIBUTING.md).

## Recuperação Histórica

A auditoria forense concluiu que branches históricos contêm conceitos de design úteis, mas não devem ser mesclados integralmente. Trabalhos futuros recuperarão ou reimplementarão deliberadamente conceitos aprovados, preservando ao mesmo tempo a atribuição dos contribuidores.

Consulte [docs/recovery/historical-recovery.md](docs/recovery/historical-recovery.md).
