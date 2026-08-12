from __future__ import annotations

import copy
import hashlib
import os
import fnmatch
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

from platformctl.service_gitops import (
    SELF_SERVICE_APPPROJECT_PATH,
    compile_application,
    future_application_path,
    helm_values_file_path,
    load_gitops_policy,
    render_application_yaml,
    service_namespace,
    validate_gitops_policy,
    validate_self_service_appproject,
)
from platformctl.service_values import compile_values, load_profile_policy, normalize_service, render_values_yaml
from platformctl.validation import ValidationError, load_service_yaml, validate_service_document


ROOT = Path(__file__).resolve().parents[3]
VALUE_FIXTURES = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "values"
RUNTIME_SCRIPT = ROOT / "scripts" / "service-gitops" / "runtime.sh"
PYTHONPATH = str(ROOT / "tools" / "platformctl" / "src")
PLATFORM_REPO_URL = "https://github.com/Franklindot04/k8s-internal-developer-platform.git"


def render_values_for_service(service_file: Path) -> str:
    document = load_service_yaml(service_file)
    validate_service_document(document)
    return render_values_yaml(compile_values(normalize_service(document), load_profile_policy()))


class PlatformServiceGitOpsTests(unittest.TestCase):
    def test_gitops_policy_loads_with_pinned_boundary(self) -> None:
        policy = load_gitops_policy()
        self.assertEqual(policy.repo_url, PLATFORM_REPO_URL)
        self.assertEqual(policy.chart_path, "platform/helm-charts/golden-path")
        self.assertEqual(policy.target_revision, "main")
        self.assertEqual(policy.project, "self-service")
        self.assertEqual(policy.application_namespace, "argocd")
        self.assertEqual(policy.destination_server, "https://kubernetes.default.svc")
        self.assertEqual(policy.namespace_prefix, "svc-")
        self.assertEqual(policy.sync_options, ("CreateNamespace=true", "PruneLast=true"))

    def test_malformed_gitops_policy_rejects_risky_values(self) -> None:
        base = load_service_yaml(ROOT / "platform" / "self-service" / "gitops-policy.yaml")
        cases = {
            "wildcard repo": {"repoURL": "*"},
            "moving revision": {"targetRevision": "HEAD"},
            "default project": {"project": "default"},
            "external cluster": {"destinationServer": "*"},
            "unsafe chart path": {"chartPath": "../platform/helm-charts/golden-path"},
            "unsafe output root": {"valuesOutputRoot": "services/other"},
            "missing namespace creation option": {"syncOptions": ["PruneLast=true"]},
        }
        for name, override in cases.items():
            with self.subTest(name=name):
                document = copy.deepcopy(base)
                document.update(override)
                with self.assertRaises(ValidationError):
                    validate_gitops_policy(document)

    def test_self_service_appproject_is_narrow(self) -> None:
        validate_self_service_appproject()
        document = load_service_yaml(SELF_SERVICE_APPPROJECT_PATH)
        spec = document["spec"]
        self.assertEqual(spec["sourceRepos"], [PLATFORM_REPO_URL])
        self.assertEqual(spec["destinations"], [{"server": "https://kubernetes.default.svc", "namespace": "svc-*"}])
        self.assertEqual(spec["clusterResourceWhitelist"], [{"group": "", "kind": "Namespace", "name": "svc-*"}])
        self.assertNotEqual(document["metadata"]["name"], "default")
        self.assertNotIn("kube-system", yaml.safe_dump(document))
        self.assertNotIn("namespace: argocd", yaml.safe_dump(spec))

    def test_self_service_appproject_rejects_broadened_permissions(self) -> None:
        document = load_service_yaml(SELF_SERVICE_APPPROJECT_PATH)
        document["spec"]["sourceRepos"] = ["*"]
        document["spec"]["destinations"] = [{"server": "*", "namespace": "*"}]
        document["spec"]["namespaceResourceWhitelist"].append({"group": "", "kind": "Secret"})
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "appproject.yaml"
            path.write_text(yaml.safe_dump(document, sort_keys=False), encoding="utf-8")
            with self.assertRaises(ValidationError) as raised:
                validate_self_service_appproject(path)
        messages = "\n".join(raised.exception.messages)
        self.assertIn("sourceRepos", messages)
        self.assertIn("destinations", messages)
        self.assertIn("unsupported resource kinds", messages)

    def test_self_service_appproject_namespace_policies_accept_only_svc_namespaces(self) -> None:
        spec = load_service_yaml(SELF_SERVICE_APPPROJECT_PATH)["spec"]
        accepted = ["svc-orders-api"]
        rejected = ["default", "argocd", "kube-system", "team-random", "orders-api"]
        for namespace in accepted:
            with self.subTest(namespace=namespace):
                self.assertTrue(_destination_namespace_allowed(spec, namespace))
                self.assertTrue(_cluster_namespace_allowed(spec, namespace))
        for namespace in rejected:
            with self.subTest(namespace=namespace):
                self.assertFalse(_destination_namespace_allowed(spec, namespace))
                self.assertFalse(_cluster_namespace_allowed(spec, namespace))

    def test_generated_paths_are_repository_relative_and_canonical(self) -> None:
        policy = load_gitops_policy()
        self.assertEqual(future_application_path("minimal-api", policy), Path("services/minimal-api/generated/application.yaml"))
        self.assertEqual(helm_values_file_path("minimal-api", policy), "../../../services/minimal-api/generated/values.yaml")
        self.assertFalse(Path(helm_values_file_path("minimal-api", policy)).is_absolute())
        resolved = (ROOT / policy.chart_path / helm_values_file_path("minimal-api", policy)).resolve()
        expected = (ROOT / "services" / "minimal-api" / "generated" / "values.yaml").resolve()
        self.assertEqual(resolved, expected)

    def test_namespace_derivation_stays_inside_kubernetes_limit(self) -> None:
        policy = load_gitops_policy()
        self.assertEqual(service_namespace("minimal-api", policy), "svc-minimal-api")
        max_service_name = "a" * 48
        self.assertEqual(len(service_namespace(max_service_name, policy)), 52)
        with self.assertRaisesRegex(ValidationError, "exceeds 63 characters"):
            service_namespace("a" * 60, policy)

    def test_golden_applications_render_exactly(self) -> None:
        policy = load_gitops_policy()
        for fixture in sorted(VALUE_FIXTURES.iterdir()):
            if not fixture.is_dir():
                continue
            with self.subTest(fixture=fixture.name):
                service_file = next((fixture / "services").glob("*/service.yaml"))
                expected = (fixture / "expected-application.yaml").read_text(encoding="utf-8")
                document = load_service_yaml(service_file)
                validate_service_document(document)
                rendered = render_application_yaml(compile_application(normalize_service(document), policy))
                self.assertEqual(rendered, expected)
                self.assertEqual(rendered, render_application_yaml(compile_application(normalize_service(document), policy)))

    def test_application_render_hash_is_stable(self) -> None:
        service_file = VALUE_FIXTURES / "large-profile" / "services" / "large-api" / "service.yaml"
        intent = normalize_service(load_service_yaml(service_file))
        policy = load_gitops_policy()
        rendered = [render_application_yaml(compile_application(intent, policy)).encode("utf-8") for _ in range(5)]
        self.assertEqual(len({hashlib.sha256(value).hexdigest() for value in rendered}), 1)

    def test_application_is_independent_of_unmapped_metadata_and_values_content(self) -> None:
        service_file = VALUE_FIXTURES / "standard-config" / "services" / "config-api" / "service.yaml"
        document = load_service_yaml(service_file)
        changed = copy.deepcopy(document)
        changed["metadata"]["description"] = "Changed description that is intentionally not mapped into GitOps."
        changed["spec"]["config"] = {"ZZZ": "last", "AAA": "first"}
        policy = load_gitops_policy()
        first = render_application_yaml(compile_application(normalize_service(document), policy))
        second = render_application_yaml(compile_application(normalize_service(changed), policy))
        self.assertEqual(first, second)

    def test_cli_plan_prints_values_and_application_without_writes(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "marker"
            marker.write_text("unchanged", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, "-m", "platformctl", "service", "plan", str(service_file)],
                check=False,
                cwd=tmp,
                env={**os.environ, "PYTHONPATH": PYTHONPATH},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(result.returncode, 0)
            self.assertIn("[ok] future values output: services/minimal-api/generated/values.yaml", result.stdout)
            self.assertIn("--- values.yaml", result.stdout)
            self.assertIn("[ok] future application output: services/minimal-api/generated/application.yaml", result.stdout)
            self.assertIn("--- application.yaml", result.stdout)
            self.assertEqual(result.stderr, "")
            self.assertEqual(marker.read_text(encoding="utf-8"), "unchanged")

    def test_generated_application_uses_stage3_and_stage4_gitops_contracts(self) -> None:
        policy = load_gitops_policy()
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        app = compile_application(normalize_service(load_service_yaml(service_file)), policy)
        self.assertEqual(app["metadata"], {"name": "minimal-api", "namespace": "argocd"})
        self.assertEqual(app["spec"]["project"], "self-service")
        self.assertEqual(app["spec"]["source"]["repoURL"], PLATFORM_REPO_URL)
        self.assertEqual(app["spec"]["source"]["targetRevision"], "main")
        self.assertEqual(app["spec"]["source"]["path"], "platform/helm-charts/golden-path")
        self.assertEqual(app["spec"]["source"]["helm"]["releaseName"], "minimal-api")
        self.assertEqual(app["spec"]["source"]["helm"]["valueFiles"], ["../../../services/minimal-api/generated/values.yaml"])
        self.assertEqual(app["spec"]["destination"], {"server": "https://kubernetes.default.svc", "namespace": "svc-minimal-api"})
        self.assertEqual(app["spec"]["syncPolicy"]["automated"], {"prune": True, "selfHeal": True})
        self.assertEqual(app["spec"]["syncPolicy"]["syncOptions"], ["CreateNamespace=true", "PruneLast=true"])
        self.assertNotIn("finalizers", app["metadata"])

    def test_appproject_namespace_resource_whitelist_matches_rendered_stage5_kinds(self) -> None:
        rendered_kinds = _rendered_stage5_kinds()
        project_kinds = {
            (item.get("group", ""), item.get("kind", ""))
            for item in load_service_yaml(SELF_SERVICE_APPPROJECT_PATH)["spec"]["namespaceResourceWhitelist"]
        }
        self.assertEqual(
            rendered_kinds,
            {
                ("", "ConfigMap"),
                ("", "Service"),
                ("", "ServiceAccount"),
                ("apps", "Deployment"),
                ("policy", "PodDisruptionBudget"),
            },
        )
        self.assertEqual(project_kinds, rendered_kinds)

    def test_runtime_workflow_uses_compiler_backed_golden_values_fixture(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        expected_values = VALUE_FIXTURES / "minimal-single" / "expected-values.yaml"
        rendered = render_values_for_service(service_file)
        self.assertEqual(rendered, expected_values.read_text(encoding="utf-8"))

        runtime_script = RUNTIME_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("tools/platformctl/tests/fixtures/values/minimal-single/expected-values.yaml", runtime_script)
        self.assertNotIn("tools/platformctl/tests/fixtures/gitops/runtime-values.yaml", runtime_script)

    def test_runtime_script_checks_reconciliation_without_requiring_health(self) -> None:
        runtime_script = RUNTIME_SCRIPT.read_text(encoding="utf-8")
        self.assertIn(".status.sync.status", runtime_script)
        self.assertIn(".status.operationState.phase", runtime_script)
        self.assertIn(".status.conditions", runtime_script)
        self.assertIn("kubectl get namespace \"$SERVICE_GITOPS_NAMESPACE\"", runtime_script)
        self.assertIn("get deployment \"$SERVICE_GITOPS_APPLICATION\"", runtime_script)
        self.assertIn("get service \"$SERVICE_GITOPS_APPLICATION\"", runtime_script)
        self.assertIn("get serviceaccount \"$SERVICE_GITOPS_APPLICATION\"", runtime_script)
        self.assertIn("Deployment fields do not match compiler-backed values", runtime_script)
        self.assertIn("registry.test/platform/minimal-api@sha256:1111111111111111111111111111111111111111111111111111111111111111", runtime_script)
        self.assertNotIn('health_status" = "Healthy"', runtime_script)
        self.assertNotIn("readyReplicas", runtime_script)

    def test_runtime_script_uses_control_plane_readiness_without_platform_bootstrap(self) -> None:
        runtime_script = RUNTIME_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("validate_argocd_control_plane", runtime_script)
        self.assertIn("crd/applications.argoproj.io", runtime_script)
        self.assertIn("crd/appprojects.argoproj.io", runtime_script)
        self.assertIn("argocd-repo-server", runtime_script)
        self.assertIn("argocd-application-controller", runtime_script)
        self.assertNotIn('scripts/gitops/argocd.sh" validate', runtime_script)
        self.assertNotIn("gitops/argocd.sh validate", runtime_script)
        self.assertNotIn("platform-bootstrap", runtime_script)

    def test_runtime_script_matches_structured_destination_policy_rejection(self) -> None:
        runtime_script = RUNTIME_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("InvalidSpecError", runtime_script)
        self.assertIn("allowed destinations", runtime_script)
        self.assertIn("project 'self-service'", runtime_script)
        self.assertIn("Forbidden destination rejected by self-service AppProject", runtime_script)
        self.assertIn("Expected forbidden destination policy rejection was not observed", runtime_script)

        condition = (
            "InvalidSpecError application destination server 'https://kubernetes.default.svc' and "
            "namespace 'default' do not match any of the allowed destinations in project 'self-service'"
        )
        self.assertIn("InvalidSpecError", condition)
        self.assertIn("destination", condition)
        self.assertIn("allowed destinations", condition)
        self.assertIn("project 'self-service'", condition)


def _destination_namespace_allowed(spec: dict[str, object], namespace: str) -> bool:
    destinations = spec.get("destinations", [])
    if not isinstance(destinations, list):
        return False
    for destination in destinations:
        if not isinstance(destination, dict):
            continue
        if destination.get("server") == "https://kubernetes.default.svc" and fnmatch.fnmatchcase(
            namespace, str(destination.get("namespace", ""))
        ):
            return True
    return False


def _cluster_namespace_allowed(spec: dict[str, object], namespace: str) -> bool:
    whitelist = spec.get("clusterResourceWhitelist", [])
    if not isinstance(whitelist, list):
        return False
    for item in whitelist:
        if not isinstance(item, dict):
            continue
        if item.get("group") == "" and item.get("kind") == "Namespace" and fnmatch.fnmatchcase(
            namespace, str(item.get("name", ""))
        ):
            return True
    return False


def _rendered_stage5_kinds() -> set[tuple[str, str]]:
    rendered: set[tuple[str, str]] = set()
    for fixture in sorted(VALUE_FIXTURES.iterdir()):
        if not fixture.is_dir():
            continue
        result = subprocess.run(
            [
                "helm",
                "template",
                fixture.name,
                str(ROOT / "platform" / "helm-charts" / "golden-path"),
                "--namespace",
                "service-values-review",
                "--values",
                str(fixture / "expected-values.yaml"),
            ],
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr)
        for document in yaml.safe_load_all(result.stdout):
            if not isinstance(document, dict) or document.get("kind") == "Namespace":
                continue
            api_version = str(document.get("apiVersion", ""))
            group = api_version.split("/", 1)[0] if "/" in api_version else ""
            kind = str(document.get("kind", ""))
            rendered.add((group, kind))
    return rendered
