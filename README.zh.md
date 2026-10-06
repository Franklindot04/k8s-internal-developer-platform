# Kubernetes Internal Developer Platform

[English](README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

本仓库正在重建为一个以本地优先（local-first）为方法的 Kubernetes 内部开发者平台（IDP）作品集项目。目标是通过可复现的 Kubernetes 环境、GitOps 交付、可复用的 Helm golden path、开发者自助服务、软件供应链控制、策略执行、可观测性、CI/CD 和运维文档来展示实用的平台工程能力。

## 当前状态

项目已完成第 6D 阶段代表性 fixture 的可信发布里程碑。第 1 阶段建立了恢复与工程基线，第 2 阶段添加了基于 Kind 的真实本地集群基础，第 3 阶段添加了 Argo CD bootstrap 与对账证明，第 4 阶段添加了带有 GitOps 运行时验证的可复用 Helm workload 契约，第 5 阶段添加了开发者自助服务基础，第 6 阶段现在已在受保护的 `main` 分支上实现经过生产验证的可信发布，并通过权威 digest 移交。

本地 Kubernetes 基础使用 Kind 实现。Argo CD 从已固定并通过 checksum 验证的上游 manifest 安装，然后用于对账最小化的平台 bootstrap 状态和 golden path 演示 workload。第 5 阶段可以验证、规划、生成和验证 `PlatformService` 仓库 artefact。第 6 阶段已定义供应链架构、代表性构建 fixture、不可信 PR 证据路径以及通过公开权威 digest 的可信 OCI 发布路径。签名、加密 provenance 或 attestation、附加到 registry 的 attestation、Kyverno 策略、可观测性、环境晋升以及后续的应用交付工作流仍为后续阶段的目标能力。

## 目标能力

- 使用 Kind 的可复现本地 Kubernetes 平台
- 使用 Argo CD 的 GitOps 对账
- 使用 Helm 的生产级可复用应用打包
- 开发者自助服务的服务生成
- 使用 GitHub Actions 的验证和 CI/供应链工作流
- 可信 OCI 发布、不可变镜像 digest、SBOM、漏洞证据及未来 provenance
- 使用 Kyverno 的 Kubernetes 原生策略执行
- 指标、日志、追踪、告警和 SRE 运维指导
- 清晰的架构、ADR、恢复记录和路线图文档

## 架构摘要

预期平台将基础设施 bootstrap、平台能力、参考 workload、开发者工具和文档分离。本地演示路径将能够在无需强制云支出的情况下运行，同时架构为未来可选的云参考部署留出空间。

目标架构和当前仓库状态请参阅 [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md)。第 6 阶段供应链信任、artefact、证据、发布和移交契约请参阅 [docs/supply-chain-architecture.md](docs/supply-chain-architecture.md)。

已实现平台核心的简明评审路径请参阅 [docs/runbooks/platform-walkthrough.md](docs/runbooks/platform-walkthrough.md)。

## 仓库结构

- `infra/` – 集群 bootstrap、Argo CD control-plane bootstrap 配置、未来环境基础设施和平台策略 bootstrap。
- `platform/` – 通过 GitOps 管理的平台 bootstrap 状态、可复用的 Helm golden path chart 以及未来的平台附加组件和共享契约。
- `services/` – 服务意图源、平台管理的生成服务 artefact 以及未来的参考 workload。
- `tools/` – 面向开发者的工具、服务生成和仓库支持工具。
- `docs/` – 架构、ADR、恢复决策、路线图以及未来的开发者/运维文档。
- `.github/` – 仓库验证和本地平台证明工作流。
- `scripts/` – 仓库验证、本地 Kubernetes、GitOps、Helm chart 和 golden path 生命周期脚本。

详细的目录契约记录在 [docs/repository/structure-contract.md](docs/repository/structure-contract.md)。

## 路线图

实施路线图记录了已完成的 local-first 参考平台核心和可选的未来扩展领域。后续的策略、可观测性、晋升、provenance 和门户工作属于未来范围，不是审查当前核心的阻碍。

请参阅 [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md)。

## 验证

仓库包含一个小型静态验证基线：

```bash
make help
make verify-tools
make validate
```

验证检查仓库结构、Markdown 规范和内部链接、现有文件的 YAML 语法、shell 语法以及 GitHub Actions 工作流 YAML。它不会创建 Kubernetes 集群、安装 Argo CD、部署 workload、发布 artefact 或需要云凭证。

## 本地 Kubernetes

第 2 阶段使用命名的 Kind 集群提供可复现的本地 Kubernetes 基础：

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

本地平台使用集群名称 `idp-local` 和 kubeconfig 上下文 `kind-idp-local`。支持的版本、生命周期行为、验证和故障排除请参阅 [docs/local-kubernetes.md](docs/local-kubernetes.md)。

## GitOps Control Plane

第 3 阶段提供可复现的本地 Argo CD control plane 和最小的 Git 管理 bootstrap 资源：

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

GitOps bootstrap 使用 `argocd` namespace，默认从 `main` 对账 `platform-bootstrap` Application，并证明 drift 修正和托管资源的重新创建。请参阅 [docs/gitops.md](docs/gitops.md)。

## Golden Path Helm Chart

第 4 阶段为普通 HTTP 服务提供可复用的 Helm chart：

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

该 chart 通过 Argo CD 部署，使用专用的 `golden-path` AppProject 和 `golden-path-demo` Application，并验证安全默认值，包括通过 digest 固定的镜像、probes、resources、security contexts、Service 路由、ConfigMap 数据和中断处理。请参阅 [docs/golden-path.md](docs/golden-path.md)。

## 贡献

贡献使用短生命周期分支和指向 `main` 的 pull request。历史分支为归属和恢复证据而保留；不应直接用作新实现工作的基础。

请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 历史恢复

取证审计得出结论，历史分支包含有用的设计概念，但不应该整体合并。未来的工作将有意恢复或重新实施已批准的概念，同时保留贡献者归属。

请参阅 [docs/recovery/historical-recovery.md](docs/recovery/historical-recovery.md)。