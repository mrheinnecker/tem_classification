import argparse
import csv
import re
import shutil
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


def apply_crop_plan(files, crop_plan):
    if crop_plan is None:
        return files

    with crop_plan.open(newline="", encoding="utf-8") as handle:
        keep_names = {
            row["filename"]
            for row in csv.DictReader(handle, delimiter="\t")
            if parse_bool(row["keep"])
        }
    selected = [path for path in files if path.name in keep_names]
    if not selected:
        raise RuntimeError(f"Crop plan does not select any TIFF slices: {crop_plan}")
    return selected


def sample_stack(files, max_values):
    samples = []
    per_slice = max(1, max_values // len(files))

    for path in files:
        image = tifffile.imread(path)
        flat = np.asarray(image).reshape(-1)
        step = max(1, flat.size // per_slice)
        samples.append(flat[::step][:per_slice])

    return np.concatenate(samples)


def summarize_shape_groups(shape_groups):
    details = []
    for shape, names in sorted(shape_groups.items(), key=lambda item: (-len(item[1]), item[0])):
        preview = ", ".join(names[:5])
        if len(names) > 5:
            preview += f", ... ({len(names)} slices total)"
        details.append(f"  shape={shape}: {preview}")
    return details


def trim_outer_shape_mismatches(files):
    shape_groups = {}
    slice_shapes = []
    for path in files:
        with tifffile.TiffFile(path) as tif:
            shape = tuple(tif.series[0].shape)
        shape_groups.setdefault(shape, []).append(path.name)
        slice_shapes.append(shape)

    if len(shape_groups) <= 1:
        return files, [], next(iter(shape_groups))

    target_shape = max(shape_groups, key=lambda shape: len(shape_groups[shape]))
    matching_indices = [
        index for index, shape in enumerate(slice_shapes) if shape == target_shape
    ]
    first_keep = matching_indices[0]
    last_keep = matching_indices[-1]

    internal_mismatches = [
        files[index].name
        for index in range(first_keep, last_keep + 1)
        if slice_shapes[index] != target_shape
    ]
    if internal_mismatches:
        preview = ", ".join(internal_mismatches[:10])
        if len(internal_mismatches) > 10:
            preview += f", ... ({len(internal_mismatches)} internal mismatches total)"
        raise ValueError(
            "TIFF slices do not all have the same dimensions and mismatching slices "
            "occur inside the stack, so automatic outer-slice trimming is unsafe.\n"
            f"  dominant_shape={target_shape}\n"
            f"  internal_mismatches={preview}\n"
            + "\n".join(summarize_shape_groups(shape_groups))
        )

    kept_files = files[first_keep : last_keep + 1]
    dropped_rows = []
    for index, (path, shape) in enumerate(zip(files, slice_shapes)):
        if index < first_keep:
            position = "start"
        elif index > last_keep:
            position = "end"
        else:
            continue
        dropped_rows.append(
            {
                "filename": path.name,
                "action": "drop",
                "reason": "outer_xy_shape_mismatch",
                "position": position,
                "shape": "x".join(map(str, shape)),
                "retained_shape": "x".join(map(str, target_shape)),
            }
        )

    return kept_files, dropped_rows, target_shape


def write_metrics(path, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(
        description="Stage renamed HITT TIFF slices, optionally converting them to uint16."
    )
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--rename-log", required=True)
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--shape-crop-log", required=True)
    parser.add_argument("--crop-plan")
    parser.add_argument("--convert-uint16", default="TRUE")
    parser.add_argument("--lower-percentile", type=float, default=0.1)
    parser.add_argument("--upper-percentile", type=float, default=99.9)
    parser.add_argument("--sample-values", type=int, default=2_000_000)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    files = apply_crop_plan(
        find_slices(input_dir),
        Path(args.crop_plan) if args.crop_plan else None,
    )
    convert_uint16 = parse_bool(args.convert_uint16)

    if not files:
        raise RuntimeError(f"No slice_*.tif(f) files found in {input_dir}")
    if args.lower_percentile >= args.upper_percentile:
        raise ValueError("Lower percentile must be smaller than upper percentile")

    original_slice_count = len(files)
    files, shape_crop_rows, retained_shape = trim_outer_shape_mismatches(files)
    if shape_crop_rows:
        write_metrics(Path(args.shape_crop_log), shape_crop_rows)
    else:
        write_metrics(
            Path(args.shape_crop_log),
            [
                {
                    "filename": "",
                    "action": "none",
                    "reason": "all_slices_match",
                    "position": "",
                    "shape": "x".join(map(str, retained_shape)),
                    "retained_shape": "x".join(map(str, retained_shape)),
                }
            ],
        )
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    lower_limit = None
    upper_limit = None
    sample_min = None
    sample_max = None
    if convert_uint16:
        sample = sample_stack(files, args.sample_values)
        sample_min = float(np.min(sample))
        sample_max = float(np.max(sample))
        lower_limit = float(np.percentile(sample, args.lower_percentile))
        upper_limit = float(np.percentile(sample, args.upper_percentile))
        if not upper_limit > lower_limit:
            raise ValueError("Sampled percentile limits do not define a usable range")

    rename_rows = []
    clipped_low = 0
    clipped_high = 0
    pixel_count = 0

    for index, source in enumerate(files, start=1):
        target_name = f"Z{index:04d}{source.suffix.lower()}"
        target = output_dir / target_name

        if convert_uint16:
            image = tifffile.imread(source)
            pixel_count += image.size
            clipped_low += int(np.count_nonzero(image < lower_limit))
            clipped_high += int(np.count_nonzero(image > upper_limit))
            scaled = np.clip(
                (image.astype(np.float32) - lower_limit)
                / (upper_limit - lower_limit),
                0.0,
                1.0,
            )
            tifffile.imwrite(target, np.rint(scaled * 65535.0).astype(np.uint16))
        else:
            shutil.copy2(source, target)

        rename_rows.append({"old_name": source.name, "new_name": target_name})

    write_metrics(
        Path(args.metrics),
        [
            {
                "mode": "uint16" if convert_uint16 else "original_dtype",
                "slice_count": len(files),
                "slice_count_before_shape_trim": original_slice_count,
                "outer_shape_mismatch_slices_dropped": len(shape_crop_rows),
                "retained_shape": "x".join(map(str, retained_shape)),
                "lower_percentile": args.lower_percentile if convert_uint16 else "",
                "upper_percentile": args.upper_percentile if convert_uint16 else "",
                "lower_limit": lower_limit if convert_uint16 else "",
                "upper_limit": upper_limit if convert_uint16 else "",
                "sample_min": sample_min if convert_uint16 else "",
                "sample_max": sample_max if convert_uint16 else "",
                "clipped_low_fraction": clipped_low / pixel_count if pixel_count else "",
                "clipped_high_fraction": clipped_high / pixel_count if pixel_count else "",
            }
        ],
    )
    write_metrics(Path(args.rename_log), rename_rows)


if __name__ == "__main__":
    main()
