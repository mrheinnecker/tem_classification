#!/usr/bin/env python3

import argparse
from pathlib import Path
import shutil

import matplotlib.pyplot as plt
import mrcfile
import numpy as np
import pandas as pd
from scipy import ndimage as ndi


def squeeze_to_2d(data):
    if data.ndim == 2:
        return data
    if data.ndim == 3:
        return data[data.shape[0] // 2, :, :]
    raise ValueError(f"Unsupported MRC dimensionality: {data.shape}")


def robust_range(img):
    p1, p99 = np.percentile(img, (1, 99))
    return max(float(p99 - p1), 1e-6)


def normalize_for_display(img):
    p1, p99 = np.percentile(img, (1, 99))
    if p99 <= p1:
        return np.zeros_like(img, dtype=np.float32)
    return np.clip((img - p1) / (p99 - p1), 0, 1)


def fit_plane(background):
    y, x = np.indices(background.shape)
    design = np.column_stack([x.ravel(), y.ravel(), np.ones(background.size)])
    coeffs, *_ = np.linalg.lstsq(design, background.ravel(), rcond=None)
    plane = (coeffs[0] * x + coeffs[1] * y + coeffs[2]).astype(np.float32)
    return plane, coeffs


def estimate_gradient(img, downsample, background_sigma):
    small = img[::downsample, ::downsample].astype(np.float32, copy=False)
    smooth = ndi.gaussian_filter(small, sigma=background_sigma)
    plane, coeffs = fit_plane(smooth)

    image_range = robust_range(small)
    background_range = float(np.percentile(plane, 99) - np.percentile(plane, 1))
    score = background_range / image_range

    x_slope, y_slope, _ = coeffs
    if abs(x_slope) >= abs(y_slope):
        direction = "left_right"
    else:
        direction = "top_bottom"

    return {
        "score": float(score),
        "direction": direction,
        "x_slope": float(x_slope),
        "y_slope": float(y_slope),
        "coeffs": coeffs.astype(np.float32),
        "plane_small": plane,
        "smooth_small": smooth,
    }


def plane_chunk(coeffs, y0, y1, width, downsample, plane_offset):
    x = np.arange(width, dtype=np.float32) / downsample
    y = np.arange(y0, y1, dtype=np.float32)[:, None] / downsample
    return (coeffs[0] * x[None, :] + coeffs[1] * y + coeffs[2] - plane_offset).astype(
        np.float32,
        copy=False,
    )


def save_qc_png(img, corrected_img, plane_small, out_png, score, corrected, threshold, direction):
    before = normalize_for_display(img)
    after = normalize_for_display(corrected_img)
    plane = normalize_for_display(plane_small)

    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    axes[0].imshow(before, cmap="gray")
    axes[0].set_title("before")
    axes[1].imshow(plane, cmap="magma")
    axes[1].set_title("estimated gradient")
    axes[2].imshow(after, cmap="gray")
    axes[2].set_title("after" if corrected else "unchanged")

    for ax in axes:
        ax.axis("off")

    fig.suptitle(
        f"score={score:.3f}, threshold={threshold:.3f}, corrected={corrected}, direction={direction}"
    )
    plt.tight_layout()
    plt.savefig(out_png, dpi=180)
    plt.close(fig)


def copy_mrc(input_path, output_path):
    shutil.copy2(input_path, output_path)


def write_corrected_mrc_chunked(
    output_path,
    data,
    voxel_size,
    coeffs,
    downsample,
    plane_offset,
    chunk_rows,
):
    height, width = data.shape[-2:]

    with mrcfile.new_mmap(
        output_path,
        shape=data.shape,
        mrc_mode=2,
        overwrite=True,
    ) as out:
        out.voxel_size = voxel_size

        if data.ndim == 2:
            for y0 in range(0, height, chunk_rows):
                y1 = min(height, y0 + chunk_rows)
                plane = plane_chunk(coeffs, y0, y1, width, downsample, plane_offset)
                out.data[y0:y1, :] = data[y0:y1, :].astype(np.float32, copy=False) - plane
        elif data.ndim == 3:
            for z in range(data.shape[0]):
                for y0 in range(0, height, chunk_rows):
                    y1 = min(height, y0 + chunk_rows)
                    plane = plane_chunk(coeffs, y0, y1, width, downsample, plane_offset)
                    out.data[z, y0:y1, :] = (
                        data[z, y0:y1, :].astype(np.float32, copy=False) - plane
                    )
        else:
            raise ValueError(f"Unsupported MRC dimensionality: {data.shape}")


def main():
    parser = argparse.ArgumentParser(
        description="Detect and optionally correct broad low-frequency greyscale gradients in TEM MRC images."
    )
    parser.add_argument("--input", required=True, help="Input MRC file")
    parser.add_argument("--output", required=True, help="Output MRC file")
    parser.add_argument("--qc-png", required=True, help="QC PNG path")
    parser.add_argument("--metrics", required=True, help="Metrics TSV path")
    parser.add_argument("--threshold", type=float, default=0.18)
    parser.add_argument("--downsample", type=int, default=16)
    parser.add_argument("--background-sigma", type=float, default=20)
    parser.add_argument("--chunk-rows", type=int, default=2048)
    parser.add_argument(
        "--mode",
        choices=["detect_only", "auto"],
        default="auto",
        help="detect_only never changes pixels; auto corrects only above threshold.",
    )
    args = parser.parse_args()

    with mrcfile.mmap(args.input, permissive=True) as mrc:
        data = mrc.data
        voxel_size = mrc.voxel_size

        img2d = squeeze_to_2d(data)
        downsample = max(1, args.downsample)
        stats = estimate_gradient(img2d, downsample, args.background_sigma)
        should_correct = args.mode == "auto" and stats["score"] >= args.threshold

        plane_offset = float(np.median(stats["plane_small"]))
        small_preview = img2d[::downsample, ::downsample].astype(np.float32, copy=False)
        corrected_preview = (
            small_preview - (stats["plane_small"] - plane_offset)
            if should_correct
            else small_preview
        )

        if should_correct:
            write_corrected_mrc_chunked(
                args.output,
                data,
                voxel_size,
                stats["coeffs"],
                downsample,
                plane_offset,
                max(1, args.chunk_rows),
            )
        else:
            copy_mrc(args.input, args.output)

        save_qc_png(
            small_preview,
            corrected_preview,
            stats["plane_small"],
            args.qc_png,
            stats["score"],
            should_correct,
            args.threshold,
            stats["direction"],
        )

    metrics = pd.DataFrame(
        [
            {
                "input": Path(args.input).name,
                "output": Path(args.output).name,
                "gradient_score": stats["score"],
                "threshold": args.threshold,
                "corrected": should_correct,
                "direction": stats["direction"],
                "x_slope": stats["x_slope"],
                "y_slope": stats["y_slope"],
                "mode": args.mode,
            }
        ]
    )
    metrics.to_csv(args.metrics, sep="\t", index=False)

    print(metrics.to_string(index=False))


if __name__ == "__main__":
    main()
