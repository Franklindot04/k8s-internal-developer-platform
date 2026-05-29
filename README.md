# Kubernetes Internal Developer Platform

This repository contains a Kubernetes‑based Internal Developer Platform (IDP) designed to provide:

- Standardized application deployment patterns  
- GitOps‑driven delivery  
- Centralized observability  
- Self‑service workflows for application teams  
- A fully extensible service template generator with support for  
  **[language variants](ca://s?q=Explain_language_variants)**,  
  **[optional components](ca://s?q=Explain_optional_components)**,  
  **[Helm integration](ca://s?q=Explain_Helm_integration)**,  
  **[CI scaffolding](ca://s?q=Explain_CI_integration)**,  
  **[environment overlays](ca://s?q=Explain_environment_overlays)**,  
  **[metadata enrichment](ca://s?q=Explain_metadata_enrichment)**,  
  **[analytics](ca://s?q=Explain_analytics_hooks)** and  
  **[service creation telemetry](ca://s?q=Explain_service_creation_telemetry)**.

All six issues from the April 20th milestone have been reviewed and closed as of May 2026.

---

## High‑Level Components

- `infra/` – Cluster, GitOps and base infrastructure definitions  
- `platform/` – Helm charts, shared platform components and deployment standards  
- `services/` – Example application services deployed onto the platform  
- `tools/service-template/` – The service generator engine (Stage 5 scaffolding complete)  
- `docs/` – Architecture, runbooks and operational documentation  

---

## Generator Capabilities (Current Status)

The service generator currently includes scaffolding for:

- **[Template packs](ca://s?q=Explain_template_packs)**  
- Real variable rendering (Stage 6 in progress)  
- Language variant support  
- Optional component toggles  
- Helm chart integration  
- CI workflow generation  
- Environment overlays  
- Documentation generation  
- Platform compatibility checks  
- Template pack testing  
- Metadata enrichment  
- Analytics hooks  
- Publishing workflow  
- Service creation telemetry  

These features form the structural foundation.  
Functional implementation continues under Stage 6.

---

## Team Roles

- Platform / DevOps / SRE Lead: **Ajero Franklin**  
- Application Platform Engineer: **Mordecai Nathan**  
- Application Platform Engineer: **Escar Maris**  

---

## Project Status

- Active development resumed: **09 May 2026**  
- All six issues from the April 20th session have been closed  
- Last major structural milestone: *Service creation telemetry scaffolding*  
- Stage 6 (functional implementation) is now underway  
- Current focus: Implementing real variable rendering  

_Last updated: 29 May 2026 by Franklin_
