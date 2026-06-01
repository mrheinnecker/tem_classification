import argparse
import csv
import re
from pathlib import Path

import numpy as np
import tifffile


def parse_bool(value):
    return str(value).strip().lower() in {"true", "1", "yes", "y"}


def find_slices(input_dir):
    slice_files = [
        path
        for path in input_dir.iterdir()
        if path.is_file()
        and path.name.lower().startswith("slice_")
        and path.suffix.lower() in {".tif", ".tiff"}
    ]
    files = slice_files or [
        path
        for path in input_dir.iterdir()
        if path.is_file()
        and re.match(r"^Z\d+\.(?:tif|tiff)$", path.name, flags=re.IGNORECASE)
    ]
    return sorted(files, key=lambda path: int(re.search(r"\d+", path.stem).group()))


def sample_image(path, max_values):
    image = np.asarray(tifffile.imread(path)).reshape(-1)
    finite = image[np.isfinite(image)]
    if finite.size <= max_values:
        return finite
    step = max(1, finite.size // max_values)
    return finite[::step][:max_values]


def bridge_short_gaps(detected, max_gap):
    bridged = detected.copy()
    positive = np.flatnonzero(detected)
    for left, right in zip(positive[:-1], positive[1:]):
        if 0 < right - left - 1 <= max_gap:
            bridged[left + 1 : right] = True
    return bridged


def sample_for_threshold(samples, max_values=2_000_000):
    per_slice = max(1, max_values // len(samples))
    selected = []
    for sample in samples:
        step = max(1, sample.size // per_slice)
        selected.append(sample[::step][:per_slice])
    return np.concatenate(selected)


def find_runs(detected):
    runs = []
    start = None
    for index, is_detected in enumerate(detected):
        if is_detected and start is None:
            start = index
        elif not is_detected and start is not None:
            runs.append((start, index - 1))
            start = None
    if start is not None:
        runs.append((start, len(detected) - 1))
    return runs


def write_tsv(path, rows):
    with Path(path).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(
        description="Detect a conservative sample-bearing Z range in a HITT TIFF stack."
    )
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-plan", required=True)
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--enabled", default="TRUE")
    parser.add_argument("--bright-threshold", default="auto")
    parser.add_argument("--auto-percentile", type=float, default=99.0)
    parser.add_argument("--min-bright-fraction", type=float, default=0.005)
    parser.add_argument("--padding-slices", type=int, default=10)
    parser.add_argument("--bridge-gap-slices", type=int, default=3)
    parser.add_argument("--min-run-slices", type=int, default=3)
    parser.add_argument("--sample-values-per-slice", type=int, default=100_000)
    args = parser.parse_args()

    files = find_slices(Path(args.input_dir))
    if not files:
        raise RuntimeError(f"No slice_*.tif(f) files found in {args.input_dir}")
    if not 0.0 <= args.auto_percentile <= 100.0:
        raise ValueError("--auto-percentile must be between 0 and 100")
    if not 0.0 <= args.min_bright_fraction <= 1.0:
        raise ValueError("--min-bright-fraction must be between 0 and 1")
    if args.sample_values_per_slice < 1:
        raise ValueError("--sample-values-per-slice must be positive")

    samples = [sample_image(path, args.sample_values_per_slice) for path in files]
    if any(sample.size == 0 for sample in samples):
        raise ValueError("At least one TIFF slice does not contain finite values")

    enabled = parse_bool(args.enabled)
    if args.bright_threshold.strip().lower() == "auto":
        threshold_sample = sample_for_threshold(samples)
        bright_threshold = float(np.percentile(threshold_sample, args.auto_percentile))
        threshold_mode = "auto"
    else:
        threshold_sample = np.array([], dtype=np.float32)
        bright_threshold = float(args.bright_threshold)
        threshold_mode = "fixed"

    bright_fractions = np.array(
        [float(np.count_nonzero(sample >= bright_threshold) / sample.size) for sample in samples]
    )
    detected = bright_fractions >= args.min_bright_fraction
    bridged = bridge_short_gaps(detected, args.bridge_gap_slices)
    runs = [
        (start, end)
        for start, end in find_runs(bridged)
        if end - start + 1 >= args.min_run_slices
    ]

    fallback_reason = ""
    if not enabled:
        crop_start = 0
        crop_end = len(files) - 1
        fallback_reason = "cropping_disabled"
    elif not runs:
        crop_start = 0
        crop_end = len(files) - 1
        fallback_reason = "no_sample_run_detected"
    else:
        sample_start, sample_end = max(runs, key=lambda run: run[1] - run[0] + 1)
        crop_start = max(0, sample_start - args.padding_slices)
        crop_end = min(len(files) - 1, sample_end + args.padding_slices)

    plan_rows = []
    for index, (path, sample, bright_fraction) in enumerate(
        zip(files, samples, bright_fractions), start=1
    ):
        plan_rows.append(
            {
                "index": index,
                "filename": path.name,
                "keep": crop_start <= index - 1 <= crop_end,
                "detected": bool(detected[index - 1]),
                "bright_fraction": bright_fraction,
                "sample_min": float(np.min(sample)),
                "sample_max": float(np.max(sample)),
                "sample_count": sample.size,
            }
        )

    metrics_rows = [
        {
            "total_slices": len(files),
            "kept_slices": crop_end - crop_start + 1,
            "first_kept_index": crop_start + 1,
            "last_kept_index": crop_end + 1,
            "first_kept_filename": files[crop_start].name,
            "last_kept_filename": files[crop_end].name,
            "threshold_mode": threshold_mode,
            "bright_threshold": bright_threshold,
            "threshold_sample_count": threshold_sample.size,
            "auto_percentile": args.auto_percentile,
            "min_bright_fraction": args.min_bright_fraction,
            "padding_slices": args.padding_slices,
            "bridge_gap_slices": args.bridge_gap_slices,
            "min_run_slices": args.min_run_slices,
            "fallback_reason": fallback_reason,
        }
    ]
    write_tsv(args.output_plan, plan_rows)
    write_tsv(args.metrics, metrics_rows)


if __name__ == "__main__":
    main()
