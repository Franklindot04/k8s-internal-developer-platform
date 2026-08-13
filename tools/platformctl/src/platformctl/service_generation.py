from __future__ import annotations

import os
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from platformctl.service_gitops import compile_application, future_application_path, load_gitops_policy, render_application_yaml
from platformctl.service_values import (
    GENERATED_HEADER,
    ROOT,
    compile_values,
    future_values_path,
    load_profile_policy,
    normalize_service,
    render_values_yaml,
)
from platformctl.validation import ValidationError, load_service_yaml, validate_service_document


ALLOWED_GENERATED_FILES = frozenset({"values.yaml", "application.yaml"})


class GenerationError(ValidationError):
    pass


@dataclass(frozen=True)
class Artifact:
    label: str
    relative_path: Path
    path: Path
    expected: bytes


@dataclass(frozen=True)
class GenerationPlan:
    service_name: str
    source_path: Path
    service_dir: Path
    generated_dir: Path
    artifacts: tuple[Artifact, Artifact]


@dataclass(frozen=True)
class ArtifactReport:
    label: str
    relative_path: Path
    status: str


@dataclass(frozen=True)
class GenerationResult:
    reports: tuple[ArtifactReport, ArtifactReport]


ReplaceFunc = Callable[[Path, Path], None]
StageFunc = Callable[[Artifact, Path], Path]


def build_generation_plan(service_file: Path, root: Path = ROOT) -> GenerationPlan:
    root = root.resolve()
    source_path = _canonical_source_path(service_file, root)
    document = load_service_yaml(source_path)
    validate_service_document(document)
    intent = normalize_service(document)

    expected_relative = Path("services") / intent.name / "service.yaml"
    if source_path.relative_to(root) != expected_relative:
        raise GenerationError([f"service source must be located at {expected_relative.as_posix()}"])

    values_path = future_values_path(expected_relative, intent.name)
    values = compile_values(intent, load_profile_policy())
    gitops_policy = load_gitops_policy()
    application_path = future_application_path(intent.name, gitops_policy)
    application = compile_application(intent, gitops_policy)

    artifacts = (
        Artifact("values.yaml", values_path, root / values_path, render_values_yaml(values).encode("utf-8")),
        Artifact(
            "application.yaml",
            application_path,
            root / application_path,
            render_application_yaml(application).encode("utf-8"),
        ),
    )
    service_dir = source_path.parent
    return GenerationPlan(intent.name, source_path, service_dir, service_dir / "generated", artifacts)


def generate_service_artifacts(
    service_file: Path,
    root: Path = ROOT,
    *,
    stage_func: StageFunc | None = None,
    replace_func: ReplaceFunc | None = None,
) -> GenerationResult:
    plan = build_generation_plan(service_file, root)
    with _service_lock(plan.service_dir):
        before = _validate_generation_preconditions(plan)

        reports = tuple(
            ArtifactReport(
                artifact.label,
                artifact.relative_path,
                "unchanged" if before[artifact.path] == artifact.expected else "updated",
            )
            if artifact.path.exists()
            else ArtifactReport(artifact.label, artifact.relative_path, "created")
            for artifact in plan.artifacts
        )
        if all(before[artifact.path] == artifact.expected for artifact in plan.artifacts):
            return GenerationResult(reports)

        created_generated_dir = False
        if not plan.generated_dir.exists():
            plan.generated_dir.mkdir(mode=0o755)
            created_generated_dir = True

        stage_func = stage_func or _stage_artifact
        replace_func = replace_func or _atomic_replace
        staged: list[Path] = []
        replaced: list[Artifact] = []
        try:
            for artifact in plan.artifacts:
                staged.append(stage_func(artifact, plan.generated_dir))
            for artifact, staged_path in zip(plan.artifacts, staged):
                if before[artifact.path] == artifact.expected:
                    staged_path.unlink(missing_ok=True)
                    continue
                replace_func(staged_path, artifact.path)
                artifact.path.chmod(0o644)
                replaced.append(artifact)
        except Exception as error:
            _rollback(plan, before, replaced)
            raise GenerationError([f"generation failed before completion; previous generated state was restored where possible: {error}"]) from error
        finally:
            for staged_path in staged:
                staged_path.unlink(missing_ok=True)
            if created_generated_dir and plan.generated_dir.exists() and not any(plan.generated_dir.iterdir()):
                plan.generated_dir.rmdir()

        mismatches = [artifact.relative_path.as_posix() for artifact in plan.artifacts if _read_bytes(artifact.path) != artifact.expected]
        if mismatches:
            raise GenerationError([f"generated artifact verification failed: {', '.join(mismatches)}"])
        return GenerationResult(reports)


def verify_service_artifacts(service_file: Path, root: Path = ROOT) -> GenerationResult:
    plan = build_generation_plan(service_file, root)
    reports = _inspect_artifacts(plan)
    bad = [report for report in reports if report.status != "current"]
    if bad:
        raise GenerationError([f"{report.relative_path.as_posix()}: {report.status}" for report in bad])
    return GenerationResult(reports)


def inspect_service_artifacts(service_file: Path, root: Path = ROOT) -> GenerationResult:
    return GenerationResult(_inspect_artifacts(build_generation_plan(service_file, root)))


def _canonical_source_path(service_file: Path, root: Path) -> Path:
    if service_file.name != "service.yaml":
        raise GenerationError(["generate and verify require a source named services/<service>/service.yaml"])
    if service_file.is_symlink():
        raise GenerationError(["service source must not be a symlink"])
    try:
        source = service_file.resolve(strict=True)
    except OSError as error:
        raise GenerationError([f"could not resolve service source: {error}"]) from error
    if root not in [source, *source.parents]:
        raise GenerationError(["service source must resolve inside the repository"])
    if source.is_symlink():
        raise GenerationError(["service source must not be a symlink"])
    service_dir = source.parent
    if service_dir.is_symlink():
        raise GenerationError(["service directory must not be a symlink"])
    if not source.is_file():
        raise GenerationError(["service source must be a regular file"])
    try:
        relative = source.relative_to(root)
    except ValueError as error:
        raise GenerationError(["service source must resolve inside the repository"]) from error
    if len(relative.parts) != 3 or relative.parts[0] != "services" or relative.parts[2] != "service.yaml":
        raise GenerationError(["service source must be located directly at services/<service>/service.yaml"])
    return source


def _validate_generation_preconditions(plan: GenerationPlan) -> dict[Path, bytes | None]:
    _validate_generated_directory(plan.generated_dir)
    before: dict[Path, bytes | None] = {}
    errors: list[str] = []
    for artifact in plan.artifacts:
        before[artifact.path] = None
        if artifact.path.exists() or artifact.path.is_symlink():
            if artifact.path.is_symlink():
                errors.append(f"{artifact.relative_path.as_posix()} must not be a symlink")
                continue
            if not artifact.path.is_file():
                errors.append(f"{artifact.relative_path.as_posix()} must be a regular generated file")
                continue
            current = artifact.path.read_bytes()
            before[artifact.path] = current
            if not current.startswith(GENERATED_HEADER.encode("utf-8")):
                errors.append(f"refusing to overwrite unmanaged file: {artifact.relative_path.as_posix()}")
    if errors:
        raise GenerationError(errors)
    return before


def _inspect_artifacts(plan: GenerationPlan) -> tuple[ArtifactReport, ArtifactReport]:
    unexpected = _unexpected_generated_entries(plan.generated_dir)
    if unexpected:
        return tuple(ArtifactReport(artifact.label, artifact.relative_path, "unexpected-entry") for artifact in plan.artifacts)
    reports: list[ArtifactReport] = []
    for artifact in plan.artifacts:
        reports.append(ArtifactReport(artifact.label, artifact.relative_path, _artifact_status(artifact)))
    return tuple(reports)  # type: ignore[return-value]


def _artifact_status(artifact: Artifact) -> str:
    if artifact.path.is_symlink():
        return "unowned"
    if not artifact.path.exists():
        return "missing"
    if not artifact.path.is_file():
        return "unowned"
    current = artifact.path.read_bytes()
    if not current.startswith(GENERATED_HEADER.encode("utf-8")):
        return "unowned"
    if current != artifact.expected:
        return "drifted"
    return "current"


def _validate_generated_directory(generated_dir: Path) -> None:
    if generated_dir.is_symlink():
        raise GenerationError(["generated directory must not be a symlink"])
    if generated_dir.exists() and not generated_dir.is_dir():
        raise GenerationError(["generated path must be a directory"])
    unexpected = _unexpected_generated_entries(generated_dir)
    if unexpected:
        raise GenerationError([f"unexpected generated directory entry: {name}" for name in sorted(unexpected)])


def _unexpected_generated_entries(generated_dir: Path) -> set[str]:
    if not generated_dir.exists() or not generated_dir.is_dir():
        return set()
    return {path.name for path in generated_dir.iterdir() if path.name not in ALLOWED_GENERATED_FILES}


def _stage_artifact(artifact: Artifact, generated_dir: Path) -> Path:
    fd, name = tempfile.mkstemp(prefix=f".{artifact.label}.", suffix=".tmp", dir=generated_dir)
    staged_path = Path(name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(artifact.expected)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(staged_path, 0o644)
        return staged_path
    except Exception:
        staged_path.unlink(missing_ok=True)
        raise


def _atomic_replace(source: Path, target: Path) -> None:
    os.replace(source, target)


def _rollback(plan: GenerationPlan, before: dict[Path, bytes | None], replaced: list[Artifact]) -> None:
    for artifact in reversed(replaced):
        original = before[artifact.path]
        if original is None:
            artifact.path.unlink(missing_ok=True)
            continue
        rollback_path = _write_rollback_file(artifact.path, original)
        os.replace(rollback_path, artifact.path)
        artifact.path.chmod(0o644)


def _write_rollback_file(target: Path, content: bytes) -> Path:
    fd, name = tempfile.mkstemp(prefix=f".{target.name}.rollback.", suffix=".tmp", dir=target.parent)
    path = Path(name)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(path, 0o644)
        return path
    except Exception:
        path.unlink(missing_ok=True)
        raise


def _read_bytes(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError:
        return None


@contextmanager
def _service_lock(service_dir: Path):
    try:
        import fcntl
    except ImportError as error:
        raise GenerationError(["service generation requires POSIX advisory locking support"]) from error

    fd = os.open(service_dir, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)
