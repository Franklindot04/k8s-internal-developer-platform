from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import os

from jsonschema import Draft202012Validator

from platformctl.validation import ValidationError, image_repository_errors, load_schema, validate_service_file


ROOT = Path(__file__).resolve().parents[3]
VALID_FIXTURES = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "valid"
INVALID_FIXTURES = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "invalid"
PYTHONPATH = str(ROOT / "tools" / "platformctl" / "src")


class PlatformServiceValidationTests(unittest.TestCase):
    def test_schema_loads(self) -> None:
        schema = load_schema()
        self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")

    def test_schema_is_valid_draft_2020_12(self) -> None:
        Draft202012Validator.check_schema(load_schema())

    def test_valid_fixtures_succeed(self) -> None:
        for fixture in sorted(VALID_FIXTURES.glob("*.yaml")):
            with self.subTest(fixture=fixture.name):
                validate_service_file(fixture)

    def test_image_repository_authority_rules(self) -> None:
        valid_repositories = [
            "registry.test/platform/service",
            "registry.test:5000/platform/service",
            "library/service",
        ]
        invalid_repositories = {
            "registry.test:5000/platform/service:v1": "tag suffix",
            "registry.test/platform/service@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa": "digest",
            "https://registry.test/platform/service": "URL scheme",
            "registry.test/platform/service name": "whitespace",
            "registry.test/platform/service/": "end with /",
            "registry.test/platform//service": "empty path segments",
        }

        for repository in valid_repositories:
            with self.subTest(repository=repository):
                self.assertEqual(image_repository_errors(repository), [])

        for repository, message in invalid_repositories.items():
            with self.subTest(repository=repository):
                self.assertIn(message, "\n".join(image_repository_errors(repository)))

    def test_valid_health_paths(self) -> None:
        base = """
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: health-path-api
  owner: platform-team
spec:
  image:
    repository: registry.test/platform/health-path-api
    digest: sha256:5656565656565656565656565656565656565656565656565656565656565656
  runtime:
    port: 8080
    healthPath: HEALTH_PATH
  resources:
    profile: small
  availability:
    profile: single
"""
        for health_path in ["/healthz", "/ready", "/api/health"]:
            with self.subTest(health_path=health_path):
                with tempfile.TemporaryDirectory() as tmp:
                    path = Path(tmp) / "service.yaml"
                    path.write_text(base.replace("HEALTH_PATH", health_path), encoding="utf-8")
                    validate_service_file(path)

    def test_invalid_fixtures_fail_for_expected_reason(self) -> None:
        expected = {
            "duplicate-secret-reference.yaml": "duplicate Secret reference",
            "duplicate-yaml-key.yaml": "duplicate key",
            "embedded-image-digest.yaml": "digest separator",
            "embedded-image-tag.yaml": "tag suffix",
            "health-path-fragment.yaml": "does not match",
            "health-path-query.yaml": "does not match",
            "image-repository-scheme.yaml": "URL scheme",
            "image-repository-trailing-slash.yaml": "end with /",
            "image-repository-whitespace.yaml": "does not match",
            "invalid-config-key.yaml": "does not match",
            "invalid-health-path.yaml": "does not match",
            "invalid-port.yaml": "greater than the maximum",
            "invalid-resource-profile.yaml": "is not one of",
            "invalid-service-name.yaml": "does not match",
            "latest-tag-image.yaml": "digest",
            "malformed-image-repository.yaml": "empty path segments",
            "malformed-digest.yaml": "does not match",
            "missing-digest.yaml": "digest",
            "multiple-documents.yaml": "exactly one YAML document",
            "overlong-service-name.yaml": "is too long",
            "raw-secret-value.yaml": "Additional properties are not allowed",
            "reserved-config-prefix.yaml": "reserved PLATFORM_ prefix",
            "scaled-availability.yaml": "is not one of",
            "tag-only-image.yaml": "digest",
            "unknown-field.yaml": "Additional properties are not allowed",
            "unsupported-external-exposure.yaml": "Additional properties are not allowed",
        }
        self.assertEqual(set(expected), {path.name for path in INVALID_FIXTURES.glob("*.yaml")})

        for fixture_name, message in expected.items():
            with self.subTest(fixture=fixture_name):
                with self.assertRaises(ValidationError) as raised:
                    validate_service_file(INVALID_FIXTURES / fixture_name)
                self.assertIn(message, "\n".join(raised.exception.messages))

    def test_empty_document_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "service.yaml"
            path.write_text("\n", encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "empty"):
                validate_service_file(path)

    def test_aliases_fail(self) -> None:
        content = """
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: alias-api
  owner: platform-team
spec:
  image:
    repository: &repo registry.test/platform/alias-api
    digest: sha256:cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd
  runtime:
    port: 8080
    healthPath: /healthz
  resources:
    profile: small
  availability:
    profile: single
  config:
    IMAGE_REPOSITORY: *repo
"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "service.yaml"
            path.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "aliases are not supported"):
                validate_service_file(path)

    def test_merge_keys_fail(self) -> None:
        content = """
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: merge-key-api
  owner: platform-team
spec:
  image:
    repository: registry.test/platform/merge-key-api
    digest: sha256:efefefefefefefefefefefefefefefefefefefefefefefefefefefefefefefef
  runtime:
    port: 8080
    healthPath: /healthz
  resources:
    profile: small
  availability:
    profile: single
  config:
    <<:
      LOG_LEVEL: info
"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "service.yaml"
            path.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "merge keys are not supported"):
                validate_service_file(path)

    def test_custom_yaml_tags_fail(self) -> None:
        content = """
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: custom-tag-api
  owner: platform-team
spec:
  image:
    repository: registry.test/platform/custom-tag-api
    digest: sha256:1212121212121212121212121212121212121212121212121212121212121212
  runtime:
    port: 8080
    healthPath: !unsafe /healthz
  resources:
    profile: small
  availability:
    profile: single
"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "service.yaml"
            path.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "unsupported YAML"):
                validate_service_file(path)

    def test_url_style_health_path_fails_semantically(self) -> None:
        content = """
apiVersion: idp/v1alpha1
kind: PlatformService
metadata:
  name: url-health-api
  owner: platform-team
spec:
  image:
    repository: registry.test/platform/url-health-api
    digest: sha256:3434343434343434343434343434343434343434343434343434343434343434
  runtime:
    port: 8080
    healthPath: //service.test/healthz
  resources:
    profile: small
  availability:
    profile: single
"""
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "service.yaml"
            path.write_text(content, encoding="utf-8")
            with self.assertRaisesRegex(ValidationError, "not a URL or host"):
                validate_service_file(path)


class PlatformServiceCliTests(unittest.TestCase):
    def test_cli_valid_fixture_succeeds(self) -> None:
        fixture = VALID_FIXTURES / "minimal.yaml"
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "validate", str(fixture)],
            check=False,
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("PlatformService contract is valid", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_cli_invalid_fixture_is_readable(self) -> None:
        fixture = INVALID_FIXTURES / "missing-digest.yaml"
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "validate", str(fixture)],
            check=False,
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("validation failed", result.stderr)
        self.assertIn("digest", result.stderr)
        self.assertNotIn("Traceback", result.stderr)

    def test_cli_works_from_nested_repository_directory(self) -> None:
        fixture = VALID_FIXTURES / "minimal.yaml"
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "validate", str(fixture)],
            check=False,
            cwd=ROOT / "docs",
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("PlatformService contract is valid", result.stdout)

    def test_cli_works_outside_repository_with_absolute_spec_path(self) -> None:
        fixture = VALID_FIXTURES / "minimal.yaml"
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "validate", str(fixture)],
            check=False,
            cwd=tempfile.gettempdir(),
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("PlatformService contract is valid", result.stdout)

    def test_cli_unknown_command_returns_usage_error(self) -> None:
        result = subprocess.run(
            [sys.executable, "-m", "platformctl", "service", "plan"],
            check=False,
            env={**os.environ, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
