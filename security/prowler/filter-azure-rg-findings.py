#!/usr/bin/env python3
"""Filter a Prowler Azure CSV using an authoritative resource-group inventory."""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any


REQUIRED_COLUMNS = {
    "CHECK_ID",
    "PROVIDER",
    "RESOURCE_UID",
    "SEVERITY",
    "STATUS",
}


class FilterError(RuntimeError):
    """Raised when an input or generated report is unsafe to use."""


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-csv", required=True, type=Path)
    parser.add_argument("--inventory-json", required=True, type=Path)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--output-csv", required=True, type=Path)
    parser.add_argument("--metadata-json", required=True, type=Path)
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--subscription-id", required=True)
    return parser.parse_args()


def load_inventory(path: Path, resource_group: str) -> set[str]:
    try:
        with path.open(encoding="utf-8-sig") as inventory_file:
            inventory: Any = json.load(inventory_file)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FilterError(f"Azure inventory is unreadable or malformed: {error}") from error

    if not isinstance(inventory, list):
        raise FilterError("Azure inventory must be a JSON array.")

    group_marker = f"/resourcegroups/{resource_group.casefold()}/"
    resource_ids: set[str] = set()
    for index, resource in enumerate(inventory, start=1):
        if not isinstance(resource, dict):
            raise FilterError(f"Azure inventory item {index} is not an object.")
        resource_id = resource.get("id")
        if not isinstance(resource_id, str) or not resource_id.strip():
            raise FilterError(f"Azure inventory item {index} has no valid id.")
        normalized_id = resource_id.strip().rstrip("/").casefold()
        if group_marker not in f"{normalized_id}/":
            raise FilterError(
                f"Azure inventory item {index} is outside resource group {resource_group}."
            )
        resource_ids.add(normalized_id)

    return resource_ids


def load_prowler_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    try:
        with path.open(encoding="utf-8-sig", newline="") as csv_file:
            reader = csv.DictReader(csv_file, delimiter=";", strict=True)
            fieldnames = reader.fieldnames
            if not fieldnames:
                raise FilterError("Prowler CSV has no header.")
            if any(not field for field in fieldnames) or len(fieldnames) != len(set(fieldnames)):
                raise FilterError("Prowler CSV has empty or duplicate column names.")
            missing_columns = sorted(REQUIRED_COLUMNS.difference(fieldnames))
            if missing_columns:
                raise FilterError(
                    "Prowler CSV is missing required columns: " + ", ".join(missing_columns)
                )

            rows: list[dict[str, str]] = []
            for line_number, row in enumerate(reader, start=2):
                if None in row or any(value is None for value in row.values()):
                    raise FilterError(f"Prowler CSV row {line_number} has the wrong column count.")
                if not row["CHECK_ID"].strip() or not row["PROVIDER"].strip():
                    raise FilterError(f"Prowler CSV row {line_number} lacks finding identity fields.")
                if not row["STATUS"].strip() or not row["SEVERITY"].strip():
                    raise FilterError(f"Prowler CSV row {line_number} lacks status or severity.")
                rows.append(row)
    except FilterError:
        raise
    except (OSError, UnicodeError, csv.Error) as error:
        raise FilterError(f"Prowler CSV is unreadable or malformed: {error}") from error

    return fieldnames, rows


def belongs_to_inventory(
    resource_uid: str, resource_group: str, inventory_ids: set[str]
) -> bool:
    normalized_uid = resource_uid.strip().rstrip("/").casefold()
    group_marker = f"/resourcegroups/{resource_group.casefold()}/"
    if group_marker not in f"{normalized_uid}/":
        return False
    return any(
        normalized_uid == inventory_id or normalized_uid.startswith(f"{inventory_id}/")
        for inventory_id in inventory_ids
    )


def atomic_write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as output_file:
            temporary_path = Path(output_file.name)
            writer = csv.DictWriter(
                output_file,
                fieldnames=fieldnames,
                delimiter=";",
                lineterminator="\n",
                extrasaction="raise",
            )
            writer.writeheader()
            writer.writerows(rows)
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            delete=False,
        ) as output_file:
            temporary_path = Path(output_file.name)
            json.dump(payload, output_file, indent=2, sort_keys=True)
            output_file.write("\n")
            output_file.flush()
            os.fsync(output_file.fileno())
        os.replace(temporary_path, path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def run() -> int:
    arguments = parse_arguments()
    resource_group = arguments.resource_group.strip()
    subscription_id = arguments.subscription_id.strip()
    if not resource_group or "/" in resource_group:
        raise FilterError("Resource group must be a non-empty Azure resource-group name.")
    if not subscription_id:
        raise FilterError("Subscription ID must not be empty.")

    inventory_ids = load_inventory(arguments.inventory_json, resource_group)
    fieldnames, full_rows = load_prowler_csv(arguments.input_csv)
    filtered_rows = [
        row
        for row in full_rows
        if belongs_to_inventory(row["RESOURCE_UID"], resource_group, inventory_ids)
    ]

    if inventory_ids and not filtered_rows:
        raise FilterError(
            "Azure resource group is non-empty, but the filtered Prowler result is empty."
        )

    status_counts = Counter(row["STATUS"].strip().upper() for row in filtered_rows)
    severity_counts = Counter(
        row["SEVERITY"].strip().upper()
        for row in filtered_rows
        if row["STATUS"].strip().upper() == "FAIL"
    )
    metadata = {
        "timestamp": arguments.timestamp,
        "subscription_id": subscription_id,
        "resource_group": resource_group,
        "azure_resource_count": len(inventory_ids),
        "full_prowler_finding_count": len(full_rows),
        "filtered_rg_finding_count": len(filtered_rows),
        "severity_counts": {
            "critical": severity_counts["CRITICAL"],
            "high": severity_counts["HIGH"],
            "medium": severity_counts["MEDIUM"],
            "low": severity_counts["LOW"],
        },
        "filtered_status_counts": {
            "pass": status_counts["PASS"],
            "fail": status_counts["FAIL"],
        },
        "scan_success_status": "SUCCESS",
    }

    atomic_write_csv(arguments.output_csv, fieldnames, filtered_rows)
    generated_fieldnames, generated_rows = load_prowler_csv(arguments.output_csv)
    if generated_fieldnames != fieldnames or generated_rows != filtered_rows:
        arguments.output_csv.unlink(missing_ok=True)
        raise FilterError("Generated resource-group CSV failed post-write validation.")
    if any(
        not belongs_to_inventory(row["RESOURCE_UID"], resource_group, inventory_ids)
        for row in generated_rows
    ):
        arguments.output_csv.unlink(missing_ok=True)
        raise FilterError("Generated resource-group CSV contains an out-of-scope resource.")
    atomic_write_json(arguments.metadata_json, metadata)
    print(json.dumps(metadata, sort_keys=True))
    return 0


def main() -> int:
    try:
        return run()
    except FilterError as error:
        print(f"Filtering failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
