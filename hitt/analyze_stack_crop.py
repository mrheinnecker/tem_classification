import argparse
import csv
import re
import struct
import zlib
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


def render_qc_image(source):
    image = np.squeeze(np.asarray(tifffile.imread(source)))
    if image.ndim != 2:
        raise ValueError(f"Expected a 2D TIFF slice for QC rendering: {source}")
    finite = image[np.isfinite(image)]
    if finite.size == 0:
        raise ValueError(f"Cannot render QC PNG without finite values: {source}")
    lower, upper = np.percentile(finite, [0.5, 99.5])
    if not upper > lower:
        lower = float(np.min(finite))
        upper = float(np.max(finite))
    if upper > lower:
        image = np.clip((image.astype(np.float32) - lower) / (upper - lower), 0.0, 1.0)
        image = np.rint(image * 255.0).astype(np.uint8)
    else:
        image = np.zeros(image.shape, dtype=np.uint8)
    return image


def save_qc_png(image, output):
    def png_chunk(chunk_type, data):
        return (
            struct.pack(">I", len(data))
            + chunk_type
            + data
            + struct.pack(">I", zlib.crc32(chunk_type + data) & 0xFFFFFFFF)
        )

    height, width = image.shape
    scanlines = b"".join(b"\x00" + row.tobytes() for row in image)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
        + png_chunk(b"IDAT", zlib.compress(scanlines))
        + png_chunk(b"IEND", b"")
    )
    Path(output).write_bytes(png)


def save_combined_qc_png(low_source, high_source, output):
    images = [
        render_qc_image(source)
        for source in (low_source, high_source)
        if source is not None
    ]
    if not images:
        return False

    if len(images) == 1:
        combined = images[0]
    else:
        separator_width = 10
        height = max(image.shape[0] for image in images)
        width = sum(image.shape[1] for image in images) + separator_width
        combined = np.zeros((height, width), dtype=np.uint8)
        combined[:, images[0].shape[1] : images[0].shape[1] + separator_width] = 255

        x_offset = 0
        for image in images:
            y_offset = (height - image.shape[0]) // 2
            combined[y_offset : y_offset + image.shape[0], x_offset : x_offset + image.shape[1]] = image
            x_offset += image.shape[1] + separator_width

    save_qc_png(combined, output)
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Detect a conservative sample-bearing Z range in a HITT TIFF stack."
    )
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-plan", required=True)
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--qc-prefix")
    parser.add_argument("--enabled", default="TRUE")
    parser.add_argument("--bright-threshold", default="auto")
    parser.add_argument("--auto-percentile", type=float, default=99.0)
    parser.add_argument("--min-bright-fraction", type=float, default=0.005)
    parser.add_argument("--padding-slices", type=int)
    parser.add_argument("--padding-low-slices", type=int)
    parser.add_argument("--padding-high-slices", type=int)
    parser.add_argument("--manual-crop-start", default="")
    parser.add_argument("--manual-crop-end", default="")
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
    padding_low_slices = (
        args.padding_low_slices
        if args.padding_low_slices is not None
        else args.padding_slices if args.padding_slices is not None else 10
    )
    padding_high_slices = (
        args.padding_high_slices
        if args.padding_high_slices is not None
        else args.padding_slices if args.padding_slices is not None else 10
    )
    if padding_low_slices < 0 or padding_high_slices < 0:
        raise ValueError("Padding slices must not be negative")

    fallback_reason = ""
    manual_crop_requested = bool(args.manual_crop_start.strip() or args.manual_crop_end.strip())
    if manual_crop_requested:
        if not (args.manual_crop_start.strip() and args.manual_crop_end.strip()):
            raise ValueError("Manual cropping requires both crop_start and crop_end values")
        crop_start = int(args.manual_crop_start) - 1
        requested_crop_end = int(args.manual_crop_end) - 1
        crop_end = min(requested_crop_end, len(files) - 1)
        if crop_start < 0 or requested_crop_end < crop_start:
            raise ValueError(
                "Manual crop range is outside the stack bounds: "
                f"crop_start={args.manual_crop_start}, crop_end={args.manual_crop_end}, "
                f"slice_count={len(files)}"
            )
        samples = []
        bright_fractions = ["" for _ in files]
        detected = [False for _ in files]
        threshold_sample = np.array([], dtype=np.float32)
        bright_threshold = ""
        threshold_mode = "manual"
        fallback_reason = "manual_crop"
    else:
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
            crop_start = max(0, sample_start - padding_low_slices)
            crop_end = min(len(files) - 1, sample_end + padding_high_slices)

    low_qc_source = files[crop_start - 1] if crop_start > 0 else None
    high_qc_source = files[crop_end + 1] if crop_end < len(files) - 1 else None
    boundary_qc_filename = ""
    if args.qc_prefix:
        boundary_qc = Path(f"{args.qc_prefix}_excluded_edges.png")
        if save_combined_qc_png(low_qc_source, high_qc_source, boundary_qc):
            boundary_qc_filename = boundary_qc.name

    plan_rows = []
    for index, path in enumerate(files, start=1):
        sample = samples[index - 1] if samples else None
        plan_rows.append(
            {
                "index": index,
                "filename": path.name,
                "keep": crop_start <= index - 1 <= crop_end,
                "detected": bool(detected[index - 1]),
                "bright_fraction": bright_fractions[index - 1],
                "sample_min": float(np.min(sample)) if sample is not None else "",
                "sample_max": float(np.max(sample)) if sample is not None else "",
                "sample_count": sample.size if sample is not None else "",
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
            "manual_crop_start": args.manual_crop_start.strip(),
            "manual_crop_end": args.manual_crop_end.strip(),
            "threshold_mode": threshold_mode,
            "bright_threshold": bright_threshold,
            "threshold_sample_count": threshold_sample.size,
            "auto_percentile": args.auto_percentile,
            "min_bright_fraction": args.min_bright_fraction,
            "padding_low_slices": padding_low_slices,
            "padding_high_slices": padding_high_slices,
            "bridge_gap_slices": args.bridge_gap_slices,
            "min_run_slices": args.min_run_slices,
            "fallback_reason": fallback_reason,
            "low_z_last_excluded_filename": low_qc_source.name if low_qc_source else "",
            "high_z_first_excluded_filename": high_qc_source.name if high_qc_source else "",
            "boundary_qc_png": boundary_qc_filename,
        }
    ]
    write_tsv(args.output_plan, plan_rows)
    write_tsv(args.metrics, metrics_rows)


if __name__ == "__main__":
    main()
