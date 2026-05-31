import argparse
import csv
from pathlib import Path

import numpy as np
import tifffile


def find_slices(input_dir):
    return sorted(
        path
        for path in input_dir.iterdir()
        if path.is_file() and path.suffix.lower() in {".tif", ".tiff"}
    )


def main():
    parser = argparse.ArgumentParser(
        description="Extract stack-wide intensity statistics from staged TIFF slices."
    )
    parser.add_argument("--input-dir", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    files = find_slices(input_dir)
    if not files:
        raise RuntimeError(f"No TIFF slices found in {input_dir}")

    min_gray = None
    max_gray = None
    for path in files:
        image = np.asarray(tifffile.imread(path))
        finite = image[np.isfinite(image)]
        if finite.size == 0:
            continue
        slice_min = float(np.min(finite))
        slice_max = float(np.max(finite))
        min_gray = slice_min if min_gray is None else min(min_gray, slice_min)
        max_gray = slice_max if max_gray is None else max(max_gray, slice_max)

    if min_gray is None or max_gray is None:
        raise ValueError(f"No finite min/max could be computed for {input_dir}")

    row = {
        "name": args.name,
        "source_dir": input_dir.name,
        "slice_count": len(files),
        "min_gray": min_gray,
        "max_gray": max_gray,
        "contrast_limits": f"({min_gray:.6g},{max_gray:.6g})",
    }
    with Path(args.output).open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=row.keys(), delimiter="\t")
        writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    main()
