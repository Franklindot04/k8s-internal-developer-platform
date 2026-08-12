from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from platformctl.service_values import GENERATED_HEADER, ROOT, PlatformServiceIntent
from platformctl.validation import ValidationError, load_service_yaml


GITOPS_POLICY_PATH = ROOT / "platform" / "self-service" / "gitops-policy.yaml"
SELF_SERVICE_APPPROJECT_PATH = ROOT / "infra" / "gitops" / "self-service" / "appproject.yaml"
KUBERNETES_NAME_MAX_LENGTH = 63


class ApplicationDumper(yaml.SafeDumper):
    def ignore_aliases(self, data: Any) -> bool:
        return True


@dataclass(frozen=True)
class GitOpsPolicy:
    repo_url: str
    chart_path: str
    target_revision: str
    project: str
    application_namespace: str
    destination_server: str
    namespace_prefix: str
    values_output_root: str
    generated_directory: str
    values_file_name: str
    application_file_name: str
    create_namespace: bool
    automated_prune: bool
    automated_self_heal: bool
    sync_options: tuple[str, ...]


def load_gitops_policy(path: Path = GITOPS_POLICY_PATH) -> GitOpsPolicy:
    document = load_service_yaml(path)
    if not isinstance(document, dict):
        raise ValidationError(["GitOps policy must be a mapping"])
    return validate_gitops_policy(document)


def validate_gitops_policy(document: dict[str, Any]) -> GitOpsPolicy:
    errors: list[str] = []
    required = {
        "repoURL",
        "chartPath",
        "targetRevision",
        "project",
        "applicationNamespace",
        "destinationServer",
        "namespacePrefix",
        "valuesOutputRoot",
        "generatedDirectory",
        "valuesFileName",
        "applicationFileName",
        "createNamespace",
        "automated",
        "syncOptions",
    }
    missing = sorted(required - set(document))
    if missing:
        errors.append(f"GitOps policy is missing required keys: {', '.join(missing)}")

    repo_url = document.get("repoURL")
    chart_path = document.get("chartPath")
    target_revision = document.get("targetRevision")
    project = document.get("project")
    application_namespace = document.get("applicationNamespace")
    destination_server = document.get("destinationServer")
    namespace_prefix = document.get("namespacePrefix")
    values_output_root = document.get("valuesOutputRoot")
    generated_directory = document.get("generatedDirectory")
    values_file_name = document.get("valuesFileName")
    application_file_name = document.get("applicationFileName")
    create_namespace = document.get("createNamespace")
    automated = document.get("automated")
    sync_options = document.get("syncOptions")

    string_fields = {
        "repoURL": repo_url,
        "chartPath": chart_path,
        "targetRevision": target_revision,
        "project": project,
        "applicationNamespace": application_namespace,
        "destinationServer": destination_server,
        "namespacePrefix": namespace_prefix,
        "valuesOutputRoot": values_output_root,
        "generatedDirectory": generated_directory,
        "valuesFileName": values_file_name,
        "applicationFileName": application_file_name,
    }
    for key, value in string_fields.items():
        if not isinstance(value, str) or value == "":
            errors.append(f"{key} must be a non-empty string")

    if isinstance(repo_url, str) and repo_url != "https://github.com/Franklindot04/k8s-internal-developer-platform.git":
        errors.append("repoURL must match the platform repository")
    if isinstance(repo_url, str) and repo_url == "*":
        errors.append("repoURL must not be a wildcard")
    if isinstance(chart_path, str):
        errors.extend(_repository_relative_path_errors("chartPath", chart_path))
    if target_revision != "main":
        errors.append("targetRevision must be main")
    if project != "self-service":
        errors.append("project must be self-service")
    if project == "default":
        errors.append("project must not be default")
    if application_namespace != "argocd":
        errors.append("applicationNamespace must be argocd")
    if destination_server != "https://kubernetes.default.svc":
        errors.append("destinationServer must be the in-cluster Kubernetes API")
    if destination_server == "*":
        errors.append("destinationServer must not be a wildcard")
    if namespace_prefix != "svc-":
        errors.append("namespacePrefix must be svc-")
    for key, value in {
        "valuesOutputRoot": values_output_root,
        "generatedDirectory": generated_directory,
        "valuesFileName": values_file_name,
        "applicationFileName": application_file_name,
    }.items():
        if isinstance(value, str):
            errors.extend(_path_segment_errors(key, value))
    if not isinstance(create_namespace, bool):
        errors.append("createNamespace must be a boolean")
    if not isinstance(automated, dict):
        errors.append("automated must be a mapping")
        automated = {}
    if not isinstance(automated.get("prune"), bool):
        errors.append("automated.prune must be a boolean")
    if not isinstance(automated.get("selfHeal"), bool):
        errors.append("automated.selfHeal must be a boolean")
    if not isinstance(sync_options, list) or not all(isinstance(item, str) for item in sync_options):
        errors.append("syncOptions must be a list of strings")
        sync_options = []
    if create_namespace is True and "CreateNamespace=true" not in sync_options:
        errors.append("syncOptions must include CreateNamespace=true when createNamespace is true")

    if errors:
        raise ValidationError(errors)

    return GitOpsPolicy(
        repo_url=repo_url,
        chart_path=chart_path,
        target_revision=target_revision,
        project=project,
        application_namespace=application_namespace,
        destination_server=destination_server,
        namespace_prefix=namespace_prefix,
        values_output_root=values_output_root,
        generated_directory=generated_directory,
        values_file_name=values_file_name,
        application_file_name=application_file_name,
        create_namespace=create_namespace,
        automated_prune=automated["prune"],
        automated_self_heal=automated["selfHeal"],
        sync_options=tuple(sync_options),
    )


def service_namespace(service_name: str, policy: GitOpsPolicy) -> str:
    namespace = f"{policy.namespace_prefix}{service_name}"
    if len(namespace) > KUBERNETES_NAME_MAX_LENGTH:
        raise ValidationError([f"derived namespace {namespace!r} exceeds {KUBERNETES_NAME_MAX_LENGTH} characters"])
    return namespace


def future_application_path(service_name: str, policy: GitOpsPolicy) -> Path:
    return Path(policy.values_output_root) / service_name / policy.generated_directory / policy.application_file_name


def future_values_path_from_policy(service_name: str, policy: GitOpsPolicy) -> Path:
    return Path(policy.values_output_root) / service_name / policy.generated_directory / policy.values_file_name


def helm_values_file_path(service_name: str, policy: GitOpsPolicy) -> str:
    chart_path = _repo_path(policy.chart_path)
    values_path = _repo_path(str(future_values_path_from_policy(service_name, policy)))
    relative = Path(*([".."] * len(chart_path.parts))) / values_path
    resolved = (ROOT / policy.chart_path / relative).resolve()
    expected = (ROOT / values_path).resolve()
    if resolved != expected or ROOT.resolve() not in [resolved, *resolved.parents]:
        raise ValidationError(["computed Helm values file path escapes the repository"])
    return relative.as_posix()


def compile_application(intent: PlatformServiceIntent, policy: GitOpsPolicy) -> dict[str, Any]:
    namespace = service_namespace(intent.name, policy)
    values_file = helm_values_file_path(intent.name, policy)
    application = {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": intent.name,
            "namespace": policy.application_namespace,
        },
        "spec": {
            "project": policy.project,
            "source": {
                "repoURL": policy.repo_url,
                "targetRevision": policy.target_revision,
                "path": policy.chart_path,
                "helm": {
                    "releaseName": intent.name,
                    "valueFiles": [values_file],
                },
            },
            "destination": {
                "server": policy.destination_server,
                "namespace": namespace,
            },
            "syncPolicy": {
                "automated": {
                    "prune": policy.automated_prune,
                    "selfHeal": policy.automated_self_heal,
                },
                "syncOptions": list(policy.sync_options),
            },
        },
    }
    _assert_application_boundary(application)
    return application


def render_application_yaml(application: dict[str, Any]) -> str:
    body = yaml.dump(
        application,
        Dumper=ApplicationDumper,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=False,
        width=1000,
    )
    return GENERATED_HEADER + body


def validate_self_service_appproject(path: Path = SELF_SERVICE_APPPROJECT_PATH) -> None:
    document = load_service_yaml(path)
    errors: list[str] = []
    if document.get("apiVersion") != "argoproj.io/v1alpha1":
        errors.append("self-service AppProject apiVersion must be argoproj.io/v1alpha1")
    if document.get("kind") != "AppProject":
        errors.append("self-service AppProject kind must be AppProject")
    if document.get("metadata", {}).get("name") != "self-service":
        errors.append("self-service AppProject name must be self-service")
    if document.get("metadata", {}).get("namespace") != "argocd":
        errors.append("self-service AppProject namespace must be argocd")
    spec = document.get("spec", {})
    if spec.get("sourceRepos") != ["https://github.com/Franklindot04/k8s-internal-developer-platform.git"]:
        errors.append("self-service AppProject must restrict sourceRepos to the platform repository")
    if spec.get("destinations") != [{"server": "https://kubernetes.default.svc", "namespace": "svc-*"}]:
        errors.append("self-service AppProject must restrict destinations to in-cluster svc-* namespaces")
    if spec.get("clusterResourceWhitelist") != [{"group": "", "kind": "Namespace", "name": "svc-*"}]:
        errors.append("self-service AppProject must restrict Namespace creation to svc-*")
    namespace_kinds = {(item.get("group", ""), item.get("kind", "")) for item in spec.get("namespaceResourceWhitelist", [])}
    expected_kinds = {
        ("", "ConfigMap"),
        ("", "Service"),
        ("", "ServiceAccount"),
        ("apps", "Deployment"),
        ("policy", "PodDisruptionBudget"),
    }
    if namespace_kinds != expected_kinds:
        errors.append("self-service AppProject namespace resource whitelist must match Stage 5B output kinds")
    forbidden = {("*", "*"), ("", "Secret"), ("networking.k8s.io", "Ingress"), ("autoscaling", "HorizontalPodAutoscaler")}
    if namespace_kinds & forbidden:
        errors.append("self-service AppProject permits unsupported resource kinds")
    if errors:
        raise ValidationError(errors)


def _assert_application_boundary(application: dict[str, Any]) -> None:
    spec = application["spec"]
    if spec["project"] == "default":
        raise ValidationError(["generated Application must not use the default project"])
    if spec["source"]["targetRevision"] != "main":
        raise ValidationError(["generated Application targetRevision must be main"])
    if spec["destination"]["server"] != "https://kubernetes.default.svc":
        raise ValidationError(["generated Application destination server must be in-cluster"])
    if not spec["destination"]["namespace"].startswith("svc-"):
        raise ValidationError(["generated Application destination namespace must use svc- prefix"])
    value_files = spec["source"]["helm"]["valueFiles"]
    if len(value_files) != 1 or Path(value_files[0]).is_absolute():
        raise ValidationError(["generated Application must reference exactly one relative values file"])


def _repo_path(path: str) -> Path:
    errors = _repository_relative_path_errors("path", path)
    if errors:
        raise ValidationError(errors)
    return Path(path)


def _repository_relative_path_errors(field: str, value: str) -> list[str]:
    path = Path(value)
    errors: list[str] = []
    if path.is_absolute():
        errors.append(f"{field} must be repository-relative")
    if any(part in {"", "."} for part in path.parts):
        errors.append(f"{field} must not contain empty or current-directory segments")
    if ".." in path.parts:
        errors.append(f"{field} must not contain parent-directory traversal")
    return errors


def _path_segment_errors(field: str, value: str) -> list[str]:
    path = Path(value)
    errors: list[str] = []
    if path.is_absolute() or len(path.parts) != 1 or value in {"", ".", ".."}:
        errors.append(f"{field} must be a single safe path segment")
    return errors
