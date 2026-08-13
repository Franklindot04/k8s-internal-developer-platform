from __future__ import annotations

import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from platformctl.service_generation import (
    GenerationError,
    build_generation_plan,
    generate_service_artifacts,
    inspect_service_artifacts,
    verify_service_artifacts,
)
from platformctl.service_values import GENERATED_HEADER


ROOT = Path(__file__).resolve().parents[3]
VALUE_FIXTURES = ROOT / "tools" / "platformctl" / "tests" / "fixtures" / "values"
PYTHONPATH = str(ROOT / "tools" / "platformctl" / "src")


class PlatformServiceGenerationTests(unittest.TestCase):
    def test_first_generation_writes_exact_two_owned_golden_artifacts(self) -> None:
        with service_repo() as repo:
            result = generate_service_artifacts(service_file(repo), repo)

            generated = repo / "services" / "minimal-api" / "generated"
            values = generated / "values.yaml"
            application = generated / "application.yaml"
            self.assertEqual([report.status for report in result.reports], ["created", "created"])
            self.assertEqual(sorted(path.name for path in generated.iterdir()), ["application.yaml", "values.yaml"])
            self.assertEqual(values.read_text(encoding="utf-8"), expected_values())
            self.assertEqual(application.read_text(encoding="utf-8"), expected_application())
            self.assertTrue(values.read_text(encoding="utf-8").startswith(GENERATED_HEADER))
            self.assertTrue(application.read_text(encoding="utf-8").startswith(GENERATED_HEADER))
            self.assertEqual(stat.S_IMODE(values.stat().st_mode), 0o644)
            self.assertEqual(stat.S_IMODE(application.stat().st_mode), 0o644)
            self.assertEqual([report.status for report in verify_service_artifacts(service_file(repo), repo).reports], ["current", "current"])

    def test_repeated_generation_is_content_idempotent_and_verify_clean(self) -> None:
        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            values = generated_file(repo, "values.yaml")
            application = generated_file(repo, "application.yaml")
            first = (values.read_bytes(), application.read_bytes())

            result = generate_service_artifacts(service_file(repo), repo)

            self.assertEqual([report.status for report in result.reports], ["unchanged", "unchanged"])
            self.assertEqual((values.read_bytes(), application.read_bytes()), first)
            self.assertEqual(sorted(path.name for path in values.parent.iterdir()), ["application.yaml", "values.yaml"])
            self.assertEqual([report.status for report in verify_service_artifacts(service_file(repo), repo).reports], ["current", "current"])

    def test_owned_drift_is_reported_read_only_and_generate_repairs(self) -> None:
        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            values = generated_file(repo, "values.yaml")
            application = generated_file(repo, "application.yaml")
            values.write_text(GENERATED_HEADER + "fullnameOverride: drifted\n", encoding="utf-8")
            application_before = application.read_bytes()

            with self.assertRaises(GenerationError) as raised:
                verify_service_artifacts(service_file(repo), repo)

            self.assertIn("values.yaml: drifted", "\n".join(raised.exception.messages))
            self.assertEqual(application.read_bytes(), application_before)
            result = generate_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in result.reports], ["updated", "unchanged"])
            self.assertEqual(values.read_text(encoding="utf-8"), expected_values())
            self.assertEqual([report.status for report in verify_service_artifacts(service_file(repo), repo).reports], ["current", "current"])

    def test_application_drift_and_pair_drift_are_repaired(self) -> None:
        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            generated_file(repo, "application.yaml").write_text(GENERATED_HEADER + "kind: Drifted\n", encoding="utf-8")
            result = generate_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in result.reports], ["unchanged", "updated"])

            generated_file(repo, "values.yaml").write_text(GENERATED_HEADER + "fullnameOverride: drifted\n", encoding="utf-8")
            generated_file(repo, "application.yaml").write_text(GENERATED_HEADER + "kind: Drifted\n", encoding="utf-8")
            result = generate_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in result.reports], ["updated", "updated"])
            self.assertEqual(generated_file(repo, "values.yaml").read_text(encoding="utf-8"), expected_values())
            self.assertEqual(generated_file(repo, "application.yaml").read_text(encoding="utf-8"), expected_application())

    def test_missing_artifacts_are_reported_and_recreated_safely(self) -> None:
        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            generated_file(repo, "values.yaml").unlink()
            with self.assertRaises(GenerationError) as raised:
                verify_service_artifacts(service_file(repo), repo)
            self.assertIn("values.yaml: missing", "\n".join(raised.exception.messages))
            result = generate_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in result.reports], ["created", "unchanged"])

            generated_file(repo, "application.yaml").unlink()
            result = generate_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in result.reports], ["unchanged", "created"])

    def test_unowned_values_collision_refuses_without_partial_mutation(self) -> None:
        with service_repo() as repo:
            generated = generated_dir(repo)
            generated.mkdir()
            hand_written = generated / "values.yaml"
            hand_written.write_text("fullnameOverride: hand-written\n", encoding="utf-8")

            with self.assertRaisesRegex(GenerationError, "unmanaged file"):
                generate_service_artifacts(service_file(repo), repo)

            self.assertEqual(hand_written.read_text(encoding="utf-8"), "fullnameOverride: hand-written\n")
            self.assertFalse((generated / "application.yaml").exists())

    def test_unowned_application_collision_refuses_without_partial_mutation(self) -> None:
        with service_repo() as repo:
            generated = generated_dir(repo)
            generated.mkdir()
            application = generated / "application.yaml"
            application.write_text("kind: Application\n", encoding="utf-8")

            with self.assertRaisesRegex(GenerationError, "unmanaged file"):
                generate_service_artifacts(service_file(repo), repo)

            self.assertEqual(application.read_text(encoding="utf-8"), "kind: Application\n")
            self.assertFalse((generated / "values.yaml").exists())

    def test_generated_looking_without_exact_marker_is_unowned(self) -> None:
        with service_repo() as repo:
            generated = generated_dir(repo)
            generated.mkdir()
            (generated / "values.yaml").write_text("# Generated by something else.\n", encoding="utf-8")
            with self.assertRaisesRegex(GenerationError, "unmanaged file"):
                generate_service_artifacts(service_file(repo), repo)

    def test_unexpected_generated_entry_refuses_without_delete(self) -> None:
        with service_repo() as repo:
            generated = generated_dir(repo)
            generated.mkdir()
            extra = generated / "metadata.yaml"
            extra.write_text("owner: someone\n", encoding="utf-8")
            with self.assertRaisesRegex(GenerationError, "unexpected generated directory entry"):
                generate_service_artifacts(service_file(repo), repo)
            self.assertTrue(extra.exists())
            self.assertFalse((generated / "values.yaml").exists())

            inspected = inspect_service_artifacts(service_file(repo), repo)
            self.assertEqual([report.status for report in inspected.reports], ["unexpected-entry", "unexpected-entry"])

    def test_source_path_must_be_canonical_services_layout(self) -> None:
        with service_repo() as repo:
            source = service_file(repo)
            nested = repo / "services" / "minimal-api" / "nested" / "service.yaml"
            nested.parent.mkdir()
            shutil.copy2(source, nested)
            with self.assertRaisesRegex(GenerationError, "directly at services/<service>/service.yaml"):
                build_generation_plan(nested, repo)

            renamed = repo / "services" / "minimal-api" / "platform.yaml"
            shutil.copy2(source, renamed)
            with self.assertRaisesRegex(GenerationError, "services/<service>/service.yaml"):
                build_generation_plan(renamed, repo)

    def test_source_name_must_match_service_directory(self) -> None:
        with service_repo(service_name="payments-api", metadata_name="minimal-api") as repo:
            with self.assertRaisesRegex(GenerationError, "services/minimal-api/service.yaml"):
                generate_service_artifacts(repo / "services" / "payments-api" / "service.yaml", repo)

    def test_rejects_source_outside_repo_and_path_traversal(self) -> None:
        with service_repo() as repo, tempfile.TemporaryDirectory() as outside_tmp:
            outside = Path(outside_tmp) / "service.yaml"
            shutil.copy2(service_file(repo), outside)
            with self.assertRaisesRegex(GenerationError, "inside the repository"):
                build_generation_plan(outside, repo)
            escaped = repo / "services" / "minimal-api" / ".." / ".." / ".." / outside.relative_to(outside.anchor)
            with self.assertRaises(GenerationError):
                build_generation_plan(escaped, repo)

    def test_rejects_symlinked_source_service_dir_generated_dir_and_targets(self) -> None:
        with service_repo() as repo:
            source = service_file(repo)
            source.unlink()
            source.symlink_to(VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml")
            with self.assertRaisesRegex(GenerationError, "must not be a symlink"):
                generate_service_artifacts(source, repo)

        with service_repo() as repo:
            service_dir = repo / "services" / "minimal-api"
            real = repo / "real-service"
            shutil.move(str(service_dir), real)
            service_dir.symlink_to(real, target_is_directory=True)
            with self.assertRaisesRegex(GenerationError, "service source must resolve inside the repository|directly at services"):
                generate_service_artifacts(service_dir / "service.yaml", repo)

        with service_repo() as repo:
            generated_dir(repo).symlink_to(repo / "elsewhere", target_is_directory=True)
            with self.assertRaisesRegex(GenerationError, "generated directory must not be a symlink"):
                generate_service_artifacts(service_file(repo), repo)

        with service_repo() as repo:
            generated_dir(repo).mkdir()
            generated_file(repo, "values.yaml").symlink_to(repo / "target")
            with self.assertRaisesRegex(GenerationError, "must not be a symlink"):
                generate_service_artifacts(service_file(repo), repo)

        with service_repo() as repo:
            generated_dir(repo).mkdir()
            generated_file(repo, "application.yaml").symlink_to(repo / "target")
            with self.assertRaisesRegex(GenerationError, "must not be a symlink"):
                generate_service_artifacts(service_file(repo), repo)

    def test_compile_pair_before_write_when_application_compilation_fails(self) -> None:
        with service_repo() as repo:
            with mock.patch("platformctl.service_generation.compile_application", side_effect=GenerationError(["boom"])):
                with self.assertRaisesRegex(GenerationError, "boom"):
                    generate_service_artifacts(service_file(repo), repo)
            self.assertFalse(generated_dir(repo).exists())

    def test_transaction_failures_clean_temporary_files_and_roll_back(self) -> None:
        with service_repo() as repo:
            def fail_first_stage(artifact, directory):
                raise OSError("stage one failed")

            with self.assertRaisesRegex(GenerationError, "stage one failed"):
                generate_service_artifacts(service_file(repo), repo, stage_func=fail_first_stage)
            self.assertFalse(generated_dir(repo).exists())

        with service_repo() as repo:
            staged_count = 0

            def fail_second_stage(artifact, directory):
                nonlocal staged_count
                staged_count += 1
                if staged_count == 2:
                    raise OSError("stage two failed")
                return stage_default(artifact, directory)

            with self.assertRaisesRegex(GenerationError, "stage two failed"):
                generate_service_artifacts(service_file(repo), repo, stage_func=fail_second_stage)
            self.assertFalse(generated_dir(repo).exists())

        with service_repo() as repo:
            def fail_first_replace(source, target):
                raise OSError("replace one failed")

            with self.assertRaisesRegex(GenerationError, "replace one failed"):
                generate_service_artifacts(service_file(repo), repo, replace_func=fail_first_replace)
            self.assertFalse(generated_dir(repo).exists())

        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            old_values = generated_file(repo, "values.yaml").read_bytes()
            old_application = generated_file(repo, "application.yaml").read_bytes()
            generated_file(repo, "values.yaml").write_text(GENERATED_HEADER + "fullnameOverride: old-drift\n", encoding="utf-8")
            generated_file(repo, "application.yaml").write_text(GENERATED_HEADER + "kind: OldDrift\n", encoding="utf-8")
            drift_values = generated_file(repo, "values.yaml").read_bytes()
            drift_application = generated_file(repo, "application.yaml").read_bytes()
            replace_count = 0

            def fail_second_replace(source, target):
                nonlocal replace_count
                replace_count += 1
                if replace_count == 2:
                    raise OSError("replace two failed")
                os.replace(source, target)

            with self.assertRaisesRegex(GenerationError, "replace two failed"):
                generate_service_artifacts(service_file(repo), repo, replace_func=fail_second_replace)
            self.assertEqual(generated_file(repo, "values.yaml").read_bytes(), drift_values)
            self.assertEqual(generated_file(repo, "application.yaml").read_bytes(), drift_application)
            self.assertNotEqual(generated_file(repo, "values.yaml").read_bytes(), old_values)
            self.assertNotEqual(generated_file(repo, "application.yaml").read_bytes(), old_application)
            self.assertEqual([path.name for path in generated_dir(repo).iterdir() if path.name.endswith(".tmp")], [])

    def test_verify_is_read_only_for_drift_missing_and_unowned_states(self) -> None:
        with service_repo() as repo:
            generate_service_artifacts(service_file(repo), repo)
            values = generated_file(repo, "values.yaml")
            before_contents = sorted(path.name for path in generated_dir(repo).iterdir())
            values.write_text(GENERATED_HEADER + "fullnameOverride: drift\n", encoding="utf-8")
            drift_bytes = values.read_bytes()
            with self.assertRaises(GenerationError):
                verify_service_artifacts(service_file(repo), repo)
            self.assertEqual(values.read_bytes(), drift_bytes)
            self.assertEqual(sorted(path.name for path in generated_dir(repo).iterdir()), before_contents)

            values.unlink()
            with self.assertRaises(GenerationError):
                verify_service_artifacts(service_file(repo), repo)
            self.assertFalse(values.exists())

            values.write_text("hand-written\n", encoding="utf-8")
            with self.assertRaises(GenerationError):
                verify_service_artifacts(service_file(repo), repo)
            self.assertEqual(values.read_text(encoding="utf-8"), "hand-written\n")

    def test_cli_generate_verify_and_plan_behaviors(self) -> None:
        with service_repo() as repo:
            generate = run_cli(repo, "generate")
            self.assertEqual(generate.returncode, 0)
            self.assertIn("values.yaml: created", generate.stdout)
            self.assertIn("application.yaml: created", generate.stdout)
            self.assertNotIn(str(repo), generate.stdout)
            self.assertEqual(generate.stderr, "")

            verify = run_cli(repo, "verify")
            self.assertEqual(verify.returncode, 0)
            self.assertIn("values.yaml: current", verify.stdout)
            self.assertIn("application.yaml: current", verify.stdout)

            before = sorted(path.relative_to(repo) for path in repo.rglob("*"))
            plan = subprocess.run(
                [sys.executable, "-m", "platformctl", "service", "plan", str(service_file(repo))],
                check=False,
                cwd=repo,
                env={**os.environ, "PYTHONPATH": PYTHONPATH},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            after = sorted(path.relative_to(repo) for path in repo.rglob("*"))
            self.assertEqual(plan.returncode, 0)
            self.assertIn("--- values.yaml", plan.stdout)
            self.assertEqual(before, after)

    def test_normal_failures_have_no_traceback(self) -> None:
        with service_repo() as repo:
            generated_dir(repo).mkdir()
            generated_file(repo, "values.yaml").write_text("hand-written\n", encoding="utf-8")
            result = run_cli(repo, "generate")
            self.assertEqual(result.returncode, 1)
            self.assertIn("refusing to overwrite unmanaged file", result.stderr)
            self.assertNotIn("Traceback", result.stderr)

    def test_generation_module_has_no_git_or_gitops_side_effect_calls(self) -> None:
        source = (ROOT / "tools" / "platformctl" / "src" / "platformctl" / "service_generation.py").read_text(encoding="utf-8")
        forbidden = ["git add", "git commit", "git push", "gh ", "kubectl", "argocd", "ApplicationSet"]
        for token in forbidden:
            with self.subTest(token=token):
                self.assertNotIn(token, source)

    def test_generated_structure_validator_accepts_real_generator_output(self) -> None:
        result = subprocess.run(
            ["bash", "scripts/ci/test-generated-structure.sh"],
            check=False,
            cwd=ROOT,
            env={**os.environ, "PYTHON": sys.executable, "PYTHONPATH": PYTHONPATH},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("generated structure validator tests passed", result.stdout)


def service_repo(service_name: str = "minimal-api", metadata_name: str = "minimal-api"):
    return ServiceRepo(service_name, metadata_name)


class ServiceRepo:
    def __init__(self, service_name: str, metadata_name: str):
        self.service_name = service_name
        self.metadata_name = metadata_name
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name)

    def __enter__(self) -> Path:
        source = VALUE_FIXTURES / "minimal-single" / "services" / "minimal-api" / "service.yaml"
        destination_dir = self.path / "services" / self.service_name
        destination_dir.mkdir(parents=True)
        content = source.read_text(encoding="utf-8").replace("name: minimal-api", f"name: {self.metadata_name}", 1)
        destination_dir.joinpath("service.yaml").write_text(content, encoding="utf-8")
        return self.path

    def __exit__(self, exc_type, exc, tb) -> None:
        self.tmp.cleanup()


def service_file(repo: Path) -> Path:
    return repo / "services" / "minimal-api" / "service.yaml"


def generated_dir(repo: Path) -> Path:
    return repo / "services" / "minimal-api" / "generated"


def generated_file(repo: Path, name: str) -> Path:
    return generated_dir(repo) / name


def expected_values() -> str:
    return (VALUE_FIXTURES / "minimal-single" / "expected-values.yaml").read_text(encoding="utf-8")


def expected_application() -> str:
    return (VALUE_FIXTURES / "minimal-single" / "expected-application.yaml").read_text(encoding="utf-8")


def stage_default(artifact, directory):
    from platformctl.service_generation import _stage_artifact

    return _stage_artifact(artifact, directory)


def run_cli(repo: Path, command: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "platformctl", "service", command, str(service_file(repo))],
        check=False,
        cwd=repo,
        env={**os.environ, "PYTHONPATH": PYTHONPATH},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
