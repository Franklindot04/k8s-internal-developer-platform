from __future__ import annotations

import copy
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

from platformctl.service_values import (
    PROFILE_POLICY_PATH,
    ProfilePolicy,
    ResourceProfile,
    compile_values,
    future_values_path,
    load_stage4_values_schema,
    load_profile_policy,
    normalize_service,
    plan_service,
    render_values_yaml,
    stage4_container_port_bounds,
    validate_profile_policy,
)
from platformctl.validation import ValidationError, load_schema, load_service_yaml, validate_service_document


ROOT = Path(__file__).resolve().parents[3]
VALUE_FIXTURES = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "values"
PYTHONPATH = str(ROOT / "tools" / "platformctl" / "src")


class PlatformServiceValuesTests(unittest.TestCase):
    def test_profile_policy_loads_and_matches_schema_enums(self) -> None:
        policy = load_profile_policy()
        self.assertEqual(sorted(policy.resource_profiles), ["large", "medium", "small"])
        self.assertEqual(sorted(policy.availability_profiles), ["single", "standard"])

    def test_schema_profile_enums_match_profile_policy_names(self) -> None:
        schema = load_schema()
        policy = load_service_yaml(PROFILE_POLICY_PATH)
        validated = validate_profile_policy(policy, schema)
        resource_enum = schema["properties"]["spec"]["properties"]["resources"]["properties"]["profile"]["enum"]
        availability_enum = schema["properties"]["spec"]["properties"]["availability"]["properties"]["profile"]["enum"]
        self.assertEqual(set(resource_enum), set(validated.resource_profiles))
        self.assertEqual(set(availability_enum), set(validated.availability_profiles))

    def test_platformservice_runtime_port_bounds_match_stage4_chart(self) -> None:
        schema = load_schema()
        platform_port = schema["properties"]["spec"]["properties"]["runtime"]["properties"]["port"]
        stage4_minimum, stage4_maximum = stage4_container_port_bounds(load_stage4_values_schema())
        self.assertEqual(platform_port["minimum"], stage4_minimum)
        self.assertEqual(platform_port["maximum"], stage4_maximum)

    def test_golden_values_render_exactly(self) -> None:
        for fixture in sorted(VALUE_FIXTURES.iterdir()):
            if not fixture.is_dir():
                continue
            with self.subTest(fixture=fixture.name):
                service_file = next((fixture / "services").glob("*/service.yaml"))
                expected = (fixture / "expected-values.yaml").read_text(encoding="utf-8")
                document = load_service_yaml(service_file)
                validate_service_document(document)
                rendered = render_values_yaml(compile_values(normalize_service(document), load_profile_policy()))
                self.assertEqual(rendered, expected)
                self.assertEqual(rendered, render_values_yaml(compile_values(normalize_service(document), load_profile_policy())))

    def test_valid_minimum_port_compiles(self) -> None:
        document = load_service_yaml(ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "valid" / "minimum-port.yaml")
        validate_service_document(document)
        rendered = render_values_yaml(compile_values(normalize_service(document), load_profile_policy()))
        self.assertIn("port: 1024", rendered)

    def test_digest_image_overrides_stage4_default_tag(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        values = compile_values(normalize_service(load_service_yaml(service_file)), load_profile_policy())
        self.assertEqual(
            values["image"],
            {
                "repository": "registry.test/platform/minimal-api",
                "tag": "",
                "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111",
            },
        )

    def test_plan_returns_future_path_and_rendered_values_without_writes(self) -> None:
        fixture = VALUE_FIXTURES / "minimal-single"
        service_file = fixture / "services" / "minimal-api" / "service.yaml"
        before = sorted(path.relative_to(ROOT) for path in ROOT.rglob("*") if ".git" not in path.parts)
        plan = plan_service(service_file)
        after = sorted(path.relative_to(ROOT) for path in ROOT.rglob("*") if ".git" not in path.parts)
        self.assertEqual(plan.values_path, Path("services/minimal-api/generated/values.yaml"))
        self.assertEqual(plan.values_yaml, (fixture / "expected-values.yaml").read_text(encoding="utf-8"))
        self.assertEqual(plan.application_path, Path("services/minimal-api/generated/application.yaml"))
        self.assertIn("kind: Application", plan.application_yaml)
        self.assertEqual(before, after)

    def test_future_path_requires_services_layout(self) -> None:
        with self.assertRaisesRegex(ValidationError, "services/<service>/service.yaml"):
            future_values_path(Path("minimal-api/service.yaml"), "minimal-api")
        with self.assertRaisesRegex(ValidationError, "service directory must match"):
            future_values_path(Path("services/wrong-name/service.yaml"), "minimal-api")
        with self.assertRaisesRegex(ValidationError, "file named service.yaml"):
            future_values_path(Path("services/minimal-api/platform.yaml"), "minimal-api")

    def test_config_key_order_is_semantically_deterministic(self) -> None:
        base_file = VALUE_FIXTURES / "standard-config" / "services" / "config-api" / "service.yaml"
        document = load_service_yaml(base_file)
        reordered = copy.deepcopy(document)
        reordered["spec"]["config"] = {
            "LOG_LEVEL": "info",
            "CACHE_TTL_SECONDS": "30",
            "APP_MODE": "review",
        }
        first = render_values_yaml(compile_values(normalize_service(document), load_profile_policy()))
        second = render_values_yaml(compile_values(normalize_service(reordered), load_profile_policy()))
        self.assertEqual(first, second)

    def test_secret_reference_order_is_semantically_deterministic(self) -> None:
        base_file = VALUE_FIXTURES / "standard-secrets" / "services" / "secret-api" / "service.yaml"
        document = load_service_yaml(base_file)
        reordered = copy.deepcopy(document)
        reordered["spec"]["secrets"]["envFrom"] = ["database-credentials", "runtime-settings"]
        first = render_values_yaml(compile_values(normalize_service(document), load_profile_policy()))
        second = render_values_yaml(compile_values(normalize_service(reordered), load_profile_policy()))
        self.assertEqual(first, second)

    def test_render_hash_is_stable_across_repeated_compilation(self) -> None:
        service_file = VALUE_FIXTURES / "large-profile" / "services" / "large-api" / "service.yaml"
        document = load_service_yaml(service_file)
        rendered = [
            render_values_yaml(compile_values(normalize_service(document), load_profile_policy())).encode("utf-8")
            for _ in range(5)
        ]
        self.assertEqual(len({hashlib.sha256(value).hexdigest() for value in rendered}), 1)

    def test_unknown_profiles_fail_at_compiler_boundary(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        intent = normalize_service(load_service_yaml(service_file))
        bad_resource = copy.copy(intent)
        object.__setattr__(bad_resource, "resource_profile", "unknown")
        with self.assertRaisesRegex(ValidationError, "unknown resource profile"):
            compile_values(bad_resource, load_profile_policy())

        bad_availability = copy.copy(intent)
        object.__setattr__(bad_availability, "availability_profile", "unknown")
        with self.assertRaisesRegex(ValidationError, "unknown availability profile"):
            compile_values(bad_availability, load_profile_policy())

    def test_compiler_defensively_rejects_internal_port_below_stage4_minimum(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        intent = normalize_service(load_service_yaml(service_file))
        corrupted = copy.copy(intent)
        object.__setattr__(corrupted, "runtime", copy.copy(intent.runtime))
        object.__setattr__(corrupted.runtime, "port", 1023)
        with self.assertRaisesRegex(ValidationError, "outside the current golden-path chart bounds"):
            compile_values(corrupted, load_profile_policy())

    def test_malformed_policy_fails_clearly(self) -> None:
        schema = load_schema()
        malformed = {
            "resourceProfiles": {
                "small": {"requests": {"cpu": "500m", "memory": "128Mi"}, "limits": {"cpu": "100m", "memory": "64Mi"}},
                "medium": {"requests": {"cpu": "100m", "memory": "128Mi"}, "limits": {"cpu": "500m", "memory": "256Mi"}},
                "large": {"requests": {"cpu": "250m", "memory": "256Mi"}, "limits": {"cpu": "1000m", "memory": "512Mi"}},
            },
            "availabilityProfiles": {
                "single": {"replicaCount": 1, "autoscaling": {"enabled": False}, "pdb": {"enabled": False}},
                "standard": {"replicaCount": 2, "autoscaling": {"enabled": False}, "pdb": {"enabled": True}},
            },
        }
        with self.assertRaises(ValidationError) as raised:
            validate_profile_policy(malformed, schema)
        messages = "\n".join(raised.exception.messages)
        self.assertIn("CPU request must not exceed CPU limit", messages)
        self.assertIn("exactly one PDB availability field", messages)

    def test_missing_stage4_mapping_fails_defensively(self) -> None:
        service_file = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        intent = normalize_service(load_service_yaml(service_file))
        policy = ProfilePolicy(resource_profiles={}, availability_profiles=load_profile_policy().availability_profiles)
        with self.assertRaisesRegex(ValidationError, "unknown resource profile"):
            compile_values(intent, policy)

    def test_cli_plan_is_readable_and_read_only(self) -> None:
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
            self.assertIn("fullnameOverride: minimal-api", result.stdout)
            self.assertIn("[ok] future application output: services/minimal-api/generated/application.yaml", result.stdout)
            self.assertIn("kind: Application", result.stdout)
            self.assertEqual(result.stderr, "")
            self.assertEqual(marker.read_text(encoding="utf-8"), "unchanged")

    def test_cli_plan_invalid_input_has_no_traceback(self) -> None:
        invalid = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "invalid" / "missing-digest.yaml"
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "plan", str(invalid)],
            check=False,
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("plan failed", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_generated_values_are_plain_yaml(self) -> None:
        expected = VALUE_FIXTURES / "standard-secrets" / "expected-values.yaml"
        loaded = yaml.safe_load(expected.read_text(encoding="utf-8"))
        self.assertEqual(loaded["existingSecret"]["envFrom"][0]["name"], "database-credentials")
