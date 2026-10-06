# Kubernetes Internal Developer Platform

[English](README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Este repositorio se está reconstruyendo como un proyecto de portafolio de una Plataforma Interna de Desarrollo (IDP) de Kubernetes con un enfoque local-first. El objetivo es demostrar ingeniería de plataformas práctica mediante entornos reproducibles de Kubernetes, entrega GitOps, un golden path reutilizable con Helm, autoservicio para desarrolladores, controles de la cadena de suministro de software, aplicación de políticas, observabilidad, CI/CD y documentación operativa.

## Estado actual

El proyecto ha completado el hito de publicación confiable de la Etapa 6D para el fixture representativo. La Etapa 1 estableció la línea base de recuperación e ingeniería, la Etapa 2 añadió una base de clúster local real basada en Kind, la Etapa 3 añadió el arranque de Argo CD y la demostración de reconciliación, la Etapa 4 añadió un contrato reutilizable de workloads con Helm y validación del runtime mediante GitOps, la Etapa 5 añadió la base de autoservicio para desarrolladores y la Etapa 6 ahora cuenta con publicación confiable probada en la rama protegida `main` mediante una transferencia de digest autoritativa.

La base local de Kubernetes está implementada con Kind. Argo CD se instala a partir de un manifiesto upstream fijado y verificado mediante checksum, y posteriormente se utiliza para reconciliar el estado mínimo de arranque de la plataforma y el workload de demostración del golden path. La Etapa 5 puede validar, planificar, generar y verificar artefactos de repositorio `PlatformService`. La Etapa 6 ha definido la arquitectura de la cadena de suministro, el fixture representativo de compilación, la ruta de evidencia de PR no confiable y la ruta de publicación OCI confiable mediante un digest público autoritativo. La firma, la procedencia o atestación criptográfica, las atestaciones adjuntas al registro, las políticas de Kyverno, la observabilidad, la promoción entre entornos y los futuros workflows de entrega de aplicaciones siguen siendo capacidades previstas para etapas posteriores.

## Capacidades objetivo

- Plataforma local de Kubernetes reproducible mediante Kind
- Reconciliación GitOps con Argo CD
- Empaquetado reutilizable de aplicaciones con Helm de calidad de producción
- Generación de servicios mediante autoservicio para desarrolladores
- Workflows de validación y CI/cadena de suministro con GitHub Actions
- Publicación OCI confiable, digests de imágenes inmutables, SBOM, evidencia de vulnerabilidades y futura procedencia
- Aplicación de políticas nativas de Kubernetes con Kyverno
- Métricas, logs, trazas, alertas y orientación operativa de SRE
- Arquitectura clara, ADRs, registros de recuperación y documentación del roadmap

## Resumen de arquitectura

La plataforma prevista separa el arranque de infraestructura, las capacidades de la plataforma, los workloads de referencia, las herramientas para desarrolladores y la documentación. El recorrido de demostración local podrá ejecutarse sin gasto obligatorio en la nube, mientras que la arquitectura deja espacio para una futura implementación de referencia opcional en la nube.

Consulta [docs/architecture/platform-overview.md](docs/architecture/platform-overview.md) para conocer la arquitectura objetivo y el estado actual del repositorio. Consulta [docs/supply-chain-architecture.md](docs/supply-chain-architecture.md) para conocer los contratos de confianza, artefactos, evidencias, publicación y transferencia de la cadena de suministro de la Etapa 6.

Para obtener un recorrido conciso como revisor por el núcleo de la plataforma implementada, consulta [docs/runbooks/platform-walkthrough.md](docs/runbooks/platform-walkthrough.md).

## Estructura del repositorio

- `infra/` - arranque del clúster, configuración de arranque del plano de control de Argo CD, futura infraestructura de entornos y arranque de políticas de plataforma.
- `platform/` - estado de arranque de la plataforma gestionado mediante GitOps, chart golden-path reutilizable de Helm y futuros complementos y contratos compartidos de la plataforma.
- `services/` - fuentes de intención de servicios, artefactos de servicios generados y gestionados por la plataforma y futuros workloads de referencia.
- `tools/` - herramientas orientadas a desarrolladores, generación de servicios y herramientas de soporte del repositorio.
- `docs/` - arquitectura, ADRs, decisiones de recuperación, roadmap y documentación futura para desarrolladores y operadores.
- `.github/` - workflows de validación del repositorio y de demostración de la plataforma local.
- `scripts/` - validación del repositorio, Kubernetes local, GitOps, chart de Helm y scripts del ciclo de vida del golden path.

El contrato detallado de directorios está documentado en [docs/repository/structure-contract.md](docs/repository/structure-contract.md).

## Roadmap

El roadmap de implementación registra el núcleo de la plataforma de referencia local-first completado y las áreas opcionales de expansión futura. El trabajo posterior sobre políticas, observabilidad, promoción, procedencia y portal forma parte del alcance futuro y no es un bloqueo para revisar el núcleo actual.

Consulta [docs/roadmap/implementation-roadmap.md](docs/roadmap/implementation-roadmap.md).

## Validación

El repositorio incluye una línea base de validación estática:

```bash
make help
make verify-tools
make validate
```

La validación comprueba la estructura del repositorio, la higiene de Markdown y los enlaces locales, la sintaxis YAML de los archivos existentes, la sintaxis de shell y los workflows YAML de GitHub Actions. No crea un clúster de Kubernetes, instala Argo CD, despliega workloads, publica artefactos ni requiere credenciales de la nube.

## Kubernetes local

La Etapa 2 proporciona una base reproducible de Kubernetes local mediante un clúster Kind con nombre:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

La plataforma local utiliza el nombre de clúster `idp-local` y el contexto kubeconfig `kind-idp-local`. Consulta [local-kubernetes.md](docs/local-kubernetes.md) para conocer las versiones compatibles, el comportamiento del ciclo de vida, la validación y la resolución de problemas.

## Plano de control GitOps

La Etapa 3 proporciona un plano de control Argo CD local reproducible y un recurso mínimo de arranque gestionado mediante Git:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

El arranque GitOps utiliza el namespace `argocd`, reconcilia la aplicación `platform-bootstrap` desde `main` de forma predeterminada y demuestra la corrección de drift y la recreación de recursos gestionados. Consulta [gitops.md](docs/gitops.md).

## Chart Helm Golden Path

La Etapa 4 proporciona un chart Helm reutilizable para servicios HTTP convencionales:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

El chart se despliega mediante Argo CD, utiliza un AppProject `golden-path` y una Application `golden-path-demo` dedicados, y valida valores predeterminados seguros, incluidos imágenes fijadas mediante digest, probes, recursos, contextos de seguridad, routing del Service, datos de ConfigMap y gestión de interrupciones. Consulta [golden-path.md](docs/golden-path.md).

## Contribuir

Las contribuciones utilizan ramas de corta duración y pull requests hacia `main`. Las ramas históricas se conservan para atribución y evidencia de recuperación; no deben utilizarse directamente como base para nuevos trabajos de implementación.

Consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Recuperación histórica

La auditoría forense concluyó que las ramas históricas contienen conceptos de diseño útiles, pero no deben fusionarse en bloque. El trabajo futuro recuperará o volverá a implementar deliberadamente los conceptos aprobados, preservando al mismo tiempo la atribución de los colaboradores.

Consulta [historical-recovery.md](docs/recovery/historical-recovery.md).
