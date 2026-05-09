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
  **[metadata enrichment](ca://s?q=Explain_metadata_enrichment)**, and  
  **[analytics + telemetry](ca://s?q=Explain_service_creation_telemetry)**.

Development resumed in **May 2026**, and several open issues from the April 20th session remain active.

---

## High‑Level Components

- `infra/` – Cluster, GitOps and base infrastructure definitions  
- `platform/` – Helm charts, shared platform components and deployment standards  
- `services/` – Example application services deployed onto the platform  
- `tools/service-template/` – The service generator engine (Stage 5 scaffolding complete)  
- `docs/` – Architecture, runbooks, and operational documentation  

---

## Generator Capabilities (Current Status)

The service generator now includes scaffolding for:

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

---

## Team Roles

- Platform / DevOps / SRE Lead: **Franklin**  
- Application Platform Engineer: **Mordecai Nathan**  
- Application Platform Engineer: **Escasr**  

---

## Project Status

- Active development resumed: **09 May 2026**  
- Last major structural milestone: *Service creation telemetry scaffolding*  
- 6 open issues remain from the April 20th session  
- Stage 6 (functional implementation) begins next  

Last updated: 09 May 2026
