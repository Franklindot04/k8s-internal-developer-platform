from __future__ import annotations

import argparse
import sys
from pathlib import Path

from platformctl.service_generation import generate_service_artifacts, verify_service_artifacts
from platformctl.service_values import plan_service
from platformctl.validation import ValidationError, validate_service_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="platformctl")
    subparsers = parser.add_subparsers(dest="resource")

    service = subparsers.add_parser("service", help="PlatformService commands")
    service_subparsers = service.add_subparsers(dest="command")

    validate = service_subparsers.add_parser("validate", help="Validate a PlatformService file")
    validate.add_argument("service_file", help="Path to service.yaml")

    plan = service_subparsers.add_parser("plan", help="Render deterministic golden-path Helm values")
    plan.add_argument("service_file", help="Path to services/<service>/service.yaml")

    generate = service_subparsers.add_parser("generate", help="Write generated service artifacts safely")
    generate.add_argument("service_file", help="Path to services/<service>/service.yaml")

    verify = service_subparsers.add_parser("verify", help="Verify generated service artifacts are current")
    verify.add_argument("service_file", help="Path to services/<service>/service.yaml")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.resource != "service" or args.command not in {"validate", "plan", "generate", "verify"}:
        parser.print_help(sys.stderr)
        return 2

    service_file = Path(args.service_file)
    if args.command == "generate":
        try:
            result = generate_service_artifacts(service_file, Path.cwd())
        except ValidationError as error:
            print("[error] service generation failed", file=sys.stderr)
            for message in error.messages:
                print(f"  - {message}", file=sys.stderr)
            return 1

        for report in result.reports:
            print(f"{report.label}: {report.status}")
        return 0

    if args.command == "verify":
        try:
            result = verify_service_artifacts(service_file, Path.cwd())
        except ValidationError as error:
            print("[error] service verification failed", file=sys.stderr)
            for message in error.messages:
                print(f"  - {message}", file=sys.stderr)
            return 1

        for report in result.reports:
            print(f"{report.label}: {report.status}")
        return 0

    if args.command == "plan":
        try:
            plan = plan_service(service_file)
        except ValidationError as error:
            print(f"[error] {service_file}: plan failed", file=sys.stderr)
            for message in error.messages:
                print(f"  - {message}", file=sys.stderr)
            return 1

        print(f"[ok] future values output: {plan.values_path}")
        print("--- values.yaml")
        print(plan.values_yaml, end="")
        print(f"[ok] future application output: {plan.application_path}")
        print("--- application.yaml")
        print(plan.application_yaml, end="")
        return 0

    try:
        validate_service_file(service_file)
    except ValidationError as error:
        print(f"[error] {service_file}: validation failed", file=sys.stderr)
        for message in error.messages:
            print(f"  - {message}", file=sys.stderr)
        return 1

    print(f"[ok] {service_file}: PlatformService contract is valid")
    return 0
