from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator, exceptions


SCHEMA_PATH = Path(__file__).resolve().parents[4] / "platform" / "self-service" / "service.schema.json"
RESERVED_CONFIG_PREFIXES = ("PLATFORM_",)
REGISTRY_COMPONENT = re.compile(r"^[a-z0-9]+([._-][a-z0-9]+)*(:[0-9]+)?$")
REPOSITORY_COMPONENT = re.compile(r"^[a-z0-9]+([._-][a-z0-9]+)*$")


class ValidationError(Exception):
    def __init__(self, messages: list[str]) -> None:
        super().__init__("\n".join(messages))
        self.messages = messages


class StrictSafeLoader(yaml.SafeLoader):
    def compose_node(self, parent: yaml.nodes.Node | None, index: Any) -> yaml.nodes.Node:
        if self.check_event(yaml.AliasEvent):
            event = self.get_event()
            raise yaml.constructor.ConstructorError(
                "while composing a node",
                None,
                f"aliases are not supported in PlatformService files: *{event.anchor}",
                event.start_mark,
            )
        return super().compose_node(parent, index)


def _construct_mapping(loader: StrictSafeLoader, node: yaml.nodes.MappingNode, deep: bool = False) -> dict[Any, Any]:
    mapping: dict[Any, Any] = {}
    for key_node, value_node in node.value:
        if key_node.tag == "tag:yaml.org,2002:merge":
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "merge keys are not supported in PlatformService files",
                key_node.start_mark,
            )
        key = loader.construct_object(key_node, deep=deep)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=deep)
    return mapping


StrictSafeLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


def load_service_yaml(path: Path) -> Any:
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValidationError([f"could not read file: {error}"]) from error

    if not content.strip():
        raise ValidationError(["YAML document is empty"])

    try:
        documents = list(yaml.load_all(content, Loader=StrictSafeLoader))
    except yaml.YAMLError as error:
        raise ValidationError([f"invalid or unsupported YAML: {error}"]) from error

    if len(documents) != 1:
        raise ValidationError(["expected exactly one YAML document"])

    document = documents[0]
    if not isinstance(document, dict):
        raise ValidationError(["top-level YAML document must be a mapping"])

    return document


def load_schema() -> dict[str, Any]:
    try:
        return json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    except OSError as error:
        raise ValidationError([f"could not read service schema: {error}"]) from error
    except json.JSONDecodeError as error:
        raise ValidationError([f"service schema is invalid JSON: {error}"]) from error


def schema_errors(document: Any, schema: dict[str, Any]) -> list[str]:
    try:
        Draft202012Validator.check_schema(schema)
    except exceptions.SchemaError as error:
        raise ValidationError([f"service schema is invalid: {error.message}"]) from error

    validator = Draft202012Validator(schema)
    return [_format_schema_error(error) for error in sorted(validator.iter_errors(document), key=str)]


def semantic_errors(document: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    spec = document.get("spec")
    if not isinstance(spec, dict):
        return errors

    image = spec.get("image")
    if isinstance(image, dict):
        if "tag" in image:
            errors.append("spec.image.tag is not supported; provide spec.image.digest only")
        repository = image.get("repository")
        if isinstance(repository, str):
            errors.extend(image_repository_errors(repository))

    runtime = spec.get("runtime")
    if isinstance(runtime, dict) and isinstance(runtime.get("healthPath"), str):
        if runtime["healthPath"].startswith("//"):
            errors.append("spec.runtime.healthPath must be an absolute path, not a URL or host")

    config = spec.get("config")
    if isinstance(config, dict):
        for key in sorted(config):
            if any(key.startswith(prefix) for prefix in RESERVED_CONFIG_PREFIXES):
                errors.append(f"spec.config.{key} uses reserved PLATFORM_ prefix")

    secrets = spec.get("secrets")
    if isinstance(secrets, dict):
        env_from = secrets.get("envFrom")
        if isinstance(env_from, list):
            seen: set[str] = set()
            for secret_name in env_from:
                if isinstance(secret_name, str):
                    if secret_name in seen:
                        errors.append(f"spec.secrets.envFrom contains duplicate Secret reference {secret_name!r}")
                    seen.add(secret_name)

    return errors


def image_repository_errors(repository: str) -> list[str]:
    errors: list[str] = []
    if "://" in repository:
        errors.append("spec.image.repository must not include a URL scheme")
    if "@" in repository:
        errors.append("spec.image.repository must not include a digest separator")
    if any(character.isspace() for character in repository):
        errors.append("spec.image.repository must not include whitespace")
    if repository.endswith("/"):
        errors.append("spec.image.repository must not end with /")
    if repository.startswith("/") or "//" in repository:
        errors.append("spec.image.repository must not contain empty path segments")

    components = repository.split("/")
    if any(component == "" for component in components):
        errors.append("spec.image.repository must not contain empty path segments")
    if components and ":" in components[-1]:
        errors.append("spec.image.repository must not include a tag suffix")

    if components:
        first_component = components[0]
        if not REGISTRY_COMPONENT.fullmatch(first_component):
            errors.append("spec.image.repository has an invalid registry or first path component")
        for component in components[1:]:
            if not REPOSITORY_COMPONENT.fullmatch(component):
                errors.append("spec.image.repository has an invalid path component")

    return sorted(set(errors))


def validate_service_file(path: Path) -> None:
    document = load_service_yaml(path)
    schema = load_schema()
    errors = schema_errors(document, schema)
    errors.extend(semantic_errors(document))
    if errors:
        raise ValidationError(errors)


def _format_schema_error(error: exceptions.ValidationError) -> str:
    location = ".".join(str(part) for part in error.absolute_path)
    prefix = f"{location}: " if location else ""
    return f"{prefix}{error.message}"
