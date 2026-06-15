import argparse
import csv
from pathlib import Path


def read_single_row_tsv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        try:
            return next(reader)
        except StopIteration:
            return {}


def dataset_from_suffix(path, suffix):
    name = path.name
    if not name.endswith(suffix):
        return path.stem
    return name[: -len(suffix)]


def find_first(root, pattern):
    matches = sorted(root.rglob(pattern))
    return matches[0] if matches else None


def summarize_crop_metrics(metrics_path):
    dataset = dataset_from_suffix(metrics_path, "_crop_metrics.tsv")
    run_dir = metrics_path.parent.parent
    metrics = read_single_row_tsv(metrics_path)

    crop_plan = metrics_path.with_name(f"{dataset}_crop_plan.tsv")
    boundary_png = metrics_path.with_name(f"{dataset}_crop_boundary_excluded_edges.png")
    shape_crop = find_first(run_dir, f"{dataset}_shape_crop.tsv")
    uint16_metrics = find_first(run_dir, f"{dataset}_uint16_metrics.tsv")

    row = {
        "dataset": dataset,
        "run_dir": str(run_dir),
        "crop_metrics_tsv": str(metrics_path),
        "crop_plan_tsv": str(crop_plan) if crop_plan.exists() else "",
        "boundary_qc_png": str(boundary_png) if boundary_png.exists() else metrics.get("boundary_qc_png", ""),
        "shape_crop_tsv": str(shape_crop) if shape_crop else "",
        "uint16_metrics_tsv": str(uint16_metrics) if uint16_metrics else "",
    }

    metric_columns = [
        "total_slices",
        "kept_slices",
        "first_kept_index",
        "last_kept_index",
        "first_kept_filename",
        "last_kept_filename",
        "manual_crop_start",
        "manual_crop_end",
        "threshold_mode",
        "bright_threshold",
        "auto_percentile",
        "min_bright_fraction",
        "padding_low_slices",
        "padding_high_slices",
        "fallback_reason",
        "low_z_last_excluded_filename",
        "high_z_first_excluded_filename",
    ]
    for column in metric_columns:
        row[column] = metrics.get(column, "")

    if shape_crop:
        shape_rows = read_all_rows_tsv(shape_crop)
        row["shape_crop_removed_slices"] = sum(
            1 for shape_row in shape_rows if shape_row.get("keep", "").lower() == "false"
        )
    else:
        row["shape_crop_removed_slices"] = ""

    if uint16_metrics:
        uint16 = read_single_row_tsv(uint16_metrics)
        for column in [
            "mode",
            "lower_limit",
            "upper_limit",
            "clipped_low_fraction",
            "clipped_high_fraction",
        ]:
            row[f"uint16_{column}"] = uint16.get(column, "")
    else:
        for column in [
            "mode",
            "lower_limit",
            "upper_limit",
            "clipped_low_fraction",
            "clipped_high_fraction",
        ]:
            row[f"uint16_{column}"] = ""

    return row


def read_all_rows_tsv(path):
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle, delimiter="\t"))


def main():
    parser = argparse.ArgumentParser(
        description="Collect HITT crop-analysis logs from one or more workflow log roots."
    )
    parser.add_argument(
        "log_roots",
        nargs="+",
        help="Workflow log directory or parent directory containing wfHITT_* runs.",
    )
    parser.add_argument(
        "--output",
        "-o",
        required=True,
        help="Output TSV summary path.",
    )
    args = parser.parse_args()

    metrics_files = []
    for root in args.log_roots:
        metrics_files.extend(Path(root).rglob("*_crop_metrics.tsv"))
    metrics_files = sorted(set(path.resolve() for path in metrics_files))

    rows = [summarize_crop_metrics(path) for path in metrics_files]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "dataset",
        "run_dir",
        "total_slices",
        "kept_slices",
        "first_kept_index",
        "last_kept_index",
        "manual_crop_start",
        "manual_crop_end",
        "threshold_mode",
        "fallback_reason",
        "boundary_qc_png",
        "shape_crop_removed_slices",
        "crop_metrics_tsv",
        "crop_plan_tsv",
        "shape_crop_tsv",
        "uint16_metrics_tsv",
        "first_kept_filename",
        "last_kept_filename",
        "low_z_last_excluded_filename",
        "high_z_first_excluded_filename",
        "bright_threshold",
        "auto_percentile",
        "min_bright_fraction",
        "padding_low_slices",
        "padding_high_slices",
        "uint16_mode",
        "uint16_lower_limit",
        "uint16_upper_limit",
        "uint16_clipped_low_fraction",
        "uint16_clipped_high_fraction",
    ]

    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} crop summaries to {output}")


if __name__ == "__main__":
    main()
