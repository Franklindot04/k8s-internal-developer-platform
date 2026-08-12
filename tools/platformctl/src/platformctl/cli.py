from __future__ import annotations

import argparse
import sys
from pathlib import Path

from platformctl.validation import ValidationError, validate_service_file


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="platformctl")
    subparsers = parser.add_subparsers(dest="resource")

    service = subparsers.add_parser("service", help="PlatformService commands")
    service_subparsers = service.add_subparsers(dest="command")

    validate = service_subparsers.add_parser("validate", help="Validate a PlatformService file")
    validate.add_argument("service_file", help="Path to service.yaml")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.resource != "service" or args.command != "validate":
        parser.print_help(sys.stderr)
        return 2

    service_file = Path(args.service_file)
    try:
        validate_service_file(service_file)
    except ValidationError as error:
        print(f"[error] {service_file}: validation failed", file=sys.stderr)
        for message in error.messages:
            print(f"  - {message}", file=sys.stderr)
        return 1

    print(f"[ok] {service_file}: PlatformService contract is valid")
    return 0
