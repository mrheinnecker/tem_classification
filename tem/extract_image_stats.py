#!/usr/bin/env python3

import argparse
from pathlib import Path
import re

import mrcfile
import numpy as np
import pandas as pd


def short_name(name):
    match = re.search(r"^(.*?c0\d+)", name)
    if match:
        return match.group(1)
    return name


def main():
    parser = argparse.ArgumentParser(description="Extract simple intensity statistics from an MRC image.")
    parser.add_argument("--input", required=True, help="Input MRC file")
    parser.add_argument("--name", required=True, help="Short image name used in the collection table")
    parser.add_argument("--output", required=True, help="Output TSV file")
    args = parser.parse_args()

    with mrcfile.mmap(args.input, permissive=True) as mrc:
        data = mrc.data
        min_gray = float(np.nanmin(data))
        max_gray = float(np.nanmax(data))

        if not np.isfinite(min_gray) or not np.isfinite(max_gray):
            raise ValueError(f"No finite min/max could be computed for {args.input}")

    pd.DataFrame(
        [
            {
                "name": short_name(args.name),
                "source_file": Path(args.input).name,
                "min_gray": min_gray,
                "max_gray": max_gray,
                "contrast_limits": f"({min_gray:.6g},{max_gray:.6g})",
            }
        ]
    ).to_csv(args.output, sep="\t", index=False)


if __name__ == "__main__":
    main()
