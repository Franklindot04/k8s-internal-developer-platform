from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from platformctl.validation import ValidationError, load_schema, load_service_yaml, validate_service_document


ROOT = Path(__file__).resolve().parents[4]
PROFILE_POLICY_PATH = ROOT / "platform" / "self-service" / "profile-policy.yaml"
STAGE4_VALUES_SCHEMA_PATH = ROOT / "platform" / "helm-charts" / "golden-path" / "values.schema.json"
GENERATED_HEADER = (
    "# Generated from ../service.yaml by the platform self-service generator.\n"
    "# Do not edit directly; update the PlatformService specification instead.\n"
)


@dataclass(frozen=True)
class ImageIntent:
    repository: str
    digest: str


@dataclass(frozen=True)
class RuntimeIntent:
    port: int
    health_path: str


@dataclass(frozen=True)
class PlatformServiceIntent:
    name: str
    owner: str
    description: str | None
    image: ImageIntent
    runtime: RuntimeIntent
    resource_profile: str
    availability_profile: str
    config: dict[str, str]
    secret_env_from: tuple[str, ...]


@dataclass(frozen=True)
class ResourceProfile:
    request_cpu: str
    request_memory: str
    limit_cpu: str
    limit_memory: str


@dataclass(frozen=True)
class AvailabilityProfile:
    replica_count: int
    autoscaling_enabled: bool
    pdb: dict[str, Any]


@dataclass(frozen=True)
class ProfilePolicy:
    resource_profiles: dict[str, ResourceProfile]
    availability_profiles: dict[str, AvailabilityProfile]


class ValuesDumper(yaml.SafeDumper):
    def ignore_aliases(self, data: Any) -> bool:
        return True


def normalize_service(document: dict[str, Any]) -> PlatformServiceIntent:
    metadata = document["metadata"]
    spec = document["spec"]
    image = spec["image"]
    runtime = spec["runtime"]
    secrets = spec.get("secrets", {})
    return PlatformServiceIntent(
        name=metadata["name"],
        owner=metadata["owner"],
        description=metadata.get("description"),
        image=ImageIntent(repository=image["repository"], digest=image["digest"]),
        runtime=RuntimeIntent(port=runtime["port"], health_path=runtime["healthPath"]),
        resource_profile=spec["resources"]["profile"],
        availability_profile=spec["availability"]["profile"],
        config={key: spec.get("config", {})[key] for key in sorted(spec.get("config", {}))},
        secret_env_from=tuple(sorted(secrets.get("envFrom", []))),
    )


def load_profile_policy(path: Path = PROFILE_POLICY_PATH) -> ProfilePolicy:
    document = load_service_yaml(path)
    if not isinstance(document, dict):
        raise ValidationError(["profile policy must be a mapping"])
    return validate_profile_policy(document, load_schema())


def load_stage4_values_schema(path: Path = STAGE4_VALUES_SCHEMA_PATH) -> dict[str, Any]:
    try:
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValidationError([f"could not read golden-path values schema: {error}"]) from error
    except yaml.YAMLError as error:
        raise ValidationError([f"golden-path values schema is invalid YAML/JSON: {error}"]) from error
    if not isinstance(document, dict):
        raise ValidationError(["golden-path values schema must be a mapping"])
    return document


def stage4_container_port_bounds(schema: dict[str, Any] | None = None) -> tuple[int, int]:
    schema = schema or load_stage4_values_schema()
    try:
        port_schema = schema["properties"]["containerPort"]["properties"]["port"]
        minimum = port_schema["minimum"]
        maximum = port_schema["maximum"]
    except KeyError as error:
        raise ValidationError(["golden-path values schema is missing containerPort.port bounds"]) from error
    if not isinstance(minimum, int) or not isinstance(maximum, int):
        raise ValidationError(["golden-path containerPort.port bounds must be integers"])
    return minimum, maximum


def validate_profile_policy(document: dict[str, Any], service_schema: dict[str, Any]) -> ProfilePolicy:
    errors: list[str] = []
    resource_profiles = document.get("resourceProfiles")
    availability_profiles = document.get("availabilityProfiles")

    if not isinstance(resource_profiles, dict):
        errors.append("resourceProfiles must be a mapping")
        resource_profiles = {}
    if not isinstance(availability_profiles, dict):
        errors.append("availabilityProfiles must be a mapping")
        availability_profiles = {}

    expected_resource_profiles = set(_schema_enum(service_schema, "resources"))
    expected_availability_profiles = set(_schema_enum(service_schema, "availability"))
    actual_resource_profiles = set(resource_profiles)
    actual_availability_profiles = set(availability_profiles)

    if actual_resource_profiles != expected_resource_profiles:
        errors.append(
            "resourceProfiles must exactly match PlatformService schema enum: "
            f"expected {sorted(expected_resource_profiles)}, found {sorted(actual_resource_profiles)}"
        )
    if actual_availability_profiles != expected_availability_profiles:
        errors.append(
            "availabilityProfiles must exactly match PlatformService schema enum: "
            f"expected {sorted(expected_availability_profiles)}, found {sorted(actual_availability_profiles)}"
        )

    parsed_resource_profiles: dict[str, ResourceProfile] = {}
    for name in sorted(resource_profiles):
        profile = resource_profiles[name]
        if not isinstance(profile, dict):
            errors.append(f"resourceProfiles.{name} must be a mapping")
            continue
        requests = profile.get("requests")
        limits = profile.get("limits")
        if not isinstance(requests, dict) or not isinstance(limits, dict):
            errors.append(f"resourceProfiles.{name} must define requests and limits")
            continue
        cpu_request = requests.get("cpu")
        memory_request = requests.get("memory")
        cpu_limit = limits.get("cpu")
        memory_limit = limits.get("memory")
        for field, value in {
            "requests.cpu": cpu_request,
            "requests.memory": memory_request,
            "limits.cpu": cpu_limit,
            "limits.memory": memory_limit,
        }.items():
            if not isinstance(value, str) or value == "":
                errors.append(f"resourceProfiles.{name}.{field} must be a non-empty string")
        if all(isinstance(value, str) and value for value in [cpu_request, memory_request, cpu_limit, memory_limit]):
            parsed_resource_profiles[name] = ResourceProfile(
                request_cpu=cpu_request,
                request_memory=memory_request,
                limit_cpu=cpu_limit,
                limit_memory=memory_limit,
            )

    _validate_resource_order(parsed_resource_profiles, errors)

    parsed_availability_profiles: dict[str, AvailabilityProfile] = {}
    for name in sorted(availability_profiles):
        profile = availability_profiles[name]
        if not isinstance(profile, dict):
            errors.append(f"availabilityProfiles.{name} must be a mapping")
            continue
        replica_count = profile.get("replicaCount")
        autoscaling = profile.get("autoscaling")
        pdb = profile.get("pdb")
        if not isinstance(replica_count, int) or replica_count < 1:
            errors.append(f"availabilityProfiles.{name}.replicaCount must be a positive integer")
        if not isinstance(autoscaling, dict) or not isinstance(autoscaling.get("enabled"), bool):
            errors.append(f"availabilityProfiles.{name}.autoscaling.enabled must be a boolean")
        if not isinstance(pdb, dict) or not isinstance(pdb.get("enabled"), bool):
            errors.append(f"availabilityProfiles.{name}.pdb.enabled must be a boolean")
            continue
        if pdb.get("enabled") is True and not (("minAvailable" in pdb) ^ ("maxUnavailable" in pdb)):
            errors.append(f"availabilityProfiles.{name}.pdb must set exactly one PDB availability field when enabled")
        if pdb.get("enabled") is False and set(pdb) != {"enabled"}:
            errors.append(f"availabilityProfiles.{name}.pdb must not set PDB policy fields when disabled")
        if isinstance(replica_count, int) and replica_count >= 1 and isinstance(autoscaling, dict) and isinstance(
            autoscaling.get("enabled"), bool
        ):
            parsed_availability_profiles[name] = AvailabilityProfile(
                replica_count=replica_count,
                autoscaling_enabled=autoscaling["enabled"],
                pdb={key: pdb[key] for key in sorted(pdb)},
            )

    if errors:
        raise ValidationError(errors)
    return ProfilePolicy(parsed_resource_profiles, parsed_availability_profiles)


def compile_values(intent: PlatformServiceIntent, policy: ProfilePolicy) -> dict[str, Any]:
    try:
        resource = policy.resource_profiles[intent.resource_profile]
    except KeyError as error:
        raise ValidationError([f"unknown resource profile: {intent.resource_profile}"]) from error
    try:
        availability = policy.availability_profiles[intent.availability_profile]
    except KeyError as error:
        raise ValidationError([f"unknown availability profile: {intent.availability_profile}"]) from error

    values: dict[str, Any] = {
        "fullnameOverride": intent.name,
        "replicaCount": availability.replica_count,
        "image": {
            "repository": intent.image.repository,
            "tag": "",
            "digest": intent.image.digest,
        },
        "containerPort": {
            "name": "http",
            "port": intent.runtime.port,
        },
        "service": {
            "type": "ClusterIP",
        },
        "probes": _probe_values(intent.runtime.health_path),
        "resources": {
            "requests": {
                "cpu": resource.request_cpu,
                "memory": resource.request_memory,
            },
            "limits": {
                "cpu": resource.limit_cpu,
                "memory": resource.limit_memory,
            },
        },
        "autoscaling": {
            "enabled": availability.autoscaling_enabled,
        },
        "pdb": availability.pdb,
        "ingress": {
            "enabled": False,
        },
    }

    if intent.config:
        values["config"] = {
            "create": True,
            "data": {key: intent.config[key] for key in sorted(intent.config)},
        }

    if intent.secret_env_from:
        values["existingSecret"] = {
            "envFrom": [{"name": name} for name in sorted(intent.secret_env_from)],
        }

    _assert_expected_stage4_mapping(values)
    return _order_values(values)


def render_values_yaml(values: dict[str, Any]) -> str:
    ordered = _order_values(values)
    body = yaml.dump(
        ordered,
        Dumper=ValuesDumper,
        default_flow_style=False,
        sort_keys=False,
        allow_unicode=False,
        width=1000,
    )
    return GENERATED_HEADER + body


def plan_service(service_file: Path) -> tuple[Path, str]:
    document = load_service_yaml(service_file)
    validate_service_document(document)
    intent = normalize_service(document)
    output_path = future_values_path(service_file, intent.name)
    values = compile_values(intent, load_profile_policy())
    return output_path, render_values_yaml(values)


def future_values_path(service_file: Path, service_name: str) -> Path:
    if service_file.name != "service.yaml":
        raise ValidationError(["plan requires a file named service.yaml"])
    service_dir = service_file.parent
    if service_dir.name != service_name:
        raise ValidationError([f"service directory must match metadata.name: expected {service_name}"])
    if service_dir.parent.name != "services":
        raise ValidationError(["service.yaml must be located at services/<service>/service.yaml for planning"])
    return Path("services") / service_name / "generated" / "values.yaml"


def _schema_enum(service_schema: dict[str, Any], section: str) -> list[str]:
    try:
        enum = service_schema["properties"]["spec"]["properties"][section]["properties"]["profile"]["enum"]
    except KeyError as error:
        raise ValidationError([f"service schema is missing spec.{section}.profile enum"]) from error
    if not isinstance(enum, list) or not all(isinstance(value, str) for value in enum):
        raise ValidationError([f"service schema spec.{section}.profile enum must be a string list"])
    return enum


def _validate_resource_order(profiles: dict[str, ResourceProfile], errors: list[str]) -> None:
    for name, profile in profiles.items():
        request_cpu = _cpu_millicores(profile.request_cpu)
        limit_cpu = _cpu_millicores(profile.limit_cpu)
        request_memory = _memory_mib(profile.request_memory)
        limit_memory = _memory_mib(profile.limit_memory)
        if min(request_cpu, limit_cpu, request_memory, limit_memory) <= 0:
            errors.append(f"resourceProfiles.{name} requests and limits must be non-zero")
        if request_cpu > limit_cpu:
            errors.append(f"resourceProfiles.{name} CPU request must not exceed CPU limit")
        if request_memory > limit_memory:
            errors.append(f"resourceProfiles.{name} memory request must not exceed memory limit")

    order = ["small", "medium", "large"]
    if all(name in profiles for name in order):
        for lower, higher in zip(order, order[1:]):
            if _cpu_millicores(profiles[lower].limit_cpu) > _cpu_millicores(profiles[higher].limit_cpu):
                errors.append("resource profile CPU limits must be monotonically increasing")
            if _memory_mib(profiles[lower].limit_memory) > _memory_mib(profiles[higher].limit_memory):
                errors.append("resource profile memory limits must be monotonically increasing")


def _cpu_millicores(value: str) -> int:
    if value.endswith("m"):
        return int(value[:-1])
    return int(value) * 1000


def _memory_mib(value: str) -> int:
    units = {"Ki": 1 / 1024, "Mi": 1, "Gi": 1024, "Ti": 1024 * 1024}
    for suffix, multiplier in units.items():
        if value.endswith(suffix):
            return int(int(value[: -len(suffix)]) * multiplier)
    return int(value)


def _probe_values(path: str) -> dict[str, Any]:
    return {
        "startup": {"enabled": True, "path": path},
        "readiness": {"enabled": True, "path": path},
        "liveness": {"enabled": True, "path": path},
    }


def _assert_expected_stage4_mapping(values: dict[str, Any]) -> None:
    required = ["image", "containerPort", "probes", "resources", "autoscaling", "pdb", "service", "ingress"]
    missing = [key for key in required if key not in values]
    if missing:
        raise ValidationError([f"compiled values are missing Stage 4 mapping keys: {', '.join(missing)}"])
    if values["autoscaling"].get("enabled") is not False:
        raise ValidationError(["PlatformService v1alpha1 values must keep autoscaling disabled"])
    if values["service"].get("type") != "ClusterIP":
        raise ValidationError(["PlatformService v1alpha1 values must keep Service type ClusterIP"])
    if values["ingress"].get("enabled") is not False:
        raise ValidationError(["PlatformService v1alpha1 values must keep ingress disabled"])
    minimum_port, maximum_port = stage4_container_port_bounds()
    port = int(values["containerPort"].get("port", 0))
    if port < minimum_port or port > maximum_port:
        raise ValidationError(["compiled runtime port is outside the current golden-path chart bounds"])


def _order_values(values: dict[str, Any]) -> dict[str, Any]:
    order = [
        "fullnameOverride",
        "replicaCount",
        "image",
        "containerPort",
        "service",
        "probes",
        "resources",
        "config",
        "existingSecret",
        "autoscaling",
        "pdb",
        "ingress",
    ]
    return {key: values[key] for key in order if key in values}
