#!/usr/bin/env python3

import argparse
import shutil
from pathlib import Path

import matplotlib.pyplot as plt
import mrcfile
import numpy as np
import zarr
from matplotlib.patches import Rectangle
from scipy import ndimage as ndi
from skimage.filters import threshold_li, threshold_otsu, threshold_yen
from skimage.measure import label, regionprops
from skimage.morphology import closing, disk, opening, remove_small_holes, remove_small_objects


def load_mrc_2d(mrc_path):
    with mrcfile.open(mrc_path, permissive=True) as mrc:
        voxel_size = mrc.voxel_size
        data = mrc.data

        if data.ndim == 2:
            img = np.array(data, dtype=np.float32, copy=True)
        elif data.ndim == 3:
            img = np.array(data[data.shape[0] // 2, :, :], dtype=np.float32, copy=True)
        else:
            raise ValueError(f"Unsupported data dimensions: {data.shape}")

    return img, voxel_size


def normalize_for_display(img):
    display = img.copy()
    p1, p99 = np.percentile(display, (1, 99))

    if p99 > p1:
        np.clip(display, p1, p99, out=display)
        display -= p1
        display /= p99 - p1
    else:
        display.fill(0)

    display *= 255.0
    return display.astype(np.uint8)


def normalize_for_segmentation(img, p_low=1, p_high=99):
    norm = img.astype(np.float32, copy=True)
    lo = np.percentile(norm, p_low)
    hi = np.percentile(norm, p_high)

    if hi <= lo:
        raise ValueError("Image has almost no intensity variation.")

    norm = (norm - lo) / (hi - lo)
    return np.clip(norm, 0, 1)


def keep_largest_object(mask):
    lab = label(mask)
    regions = regionprops(lab)
    if len(regions) == 0:
        raise ValueError("No foreground objects found after segmentation.")

    largest = max(regions, key=lambda r: r.area)
    return lab == largest.label


def make_mask(
    img,
    foreground="darker",
    sigma=5,
    threshold_scale=1.0,
    threshold_method="otsu",
    min_object_size=50_000,
    min_hole_size=50_000,
    closing_radius=15,
    opening_radius=3,
):
    norm = normalize_for_segmentation(img)
    smooth = ndi.gaussian_filter(norm, sigma=sigma)

    if threshold_method == "otsu":
        thr = threshold_otsu(smooth)
    elif threshold_method == "li":
        thr = threshold_li(smooth)
    elif threshold_method == "yen":
        thr = threshold_yen(smooth)
    else:
        raise ValueError(f"Unknown threshold method: {threshold_method}")

    thr *= threshold_scale

    if foreground == "darker":
        mask = smooth < thr
    elif foreground == "brighter":
        mask = smooth > thr
    else:
        raise ValueError("foreground must be 'darker' or 'brighter'")

    if opening_radius > 0:
        mask = opening(mask, disk(opening_radius))

    if closing_radius > 0:
        mask = closing(mask, disk(closing_radius))

    mask = ndi.binary_fill_holes(mask)
    mask = remove_small_objects(mask.astype(bool), min_size=min_object_size)
    mask = remove_small_holes(mask.astype(bool), area_threshold=min_hole_size)
    mask = keep_largest_object(mask)

    return mask.astype(bool), thr


def make_mask_background_negative(
    img,
    background="brighter",
    sigma=10,
    threshold_method="otsu",
    threshold_scale=1.0,
    min_object_size=50_000,
    min_hole_size=50_000,
    closing_radius=25,
    opening_radius=5,
):
    norm = normalize_for_segmentation(img)
    smooth = ndi.gaussian_filter(norm, sigma=sigma)

    if threshold_method == "otsu":
        thr = threshold_otsu(smooth)
    elif threshold_method == "li":
        thr = threshold_li(smooth)
    elif threshold_method == "yen":
        thr = threshold_yen(smooth)
    else:
        raise ValueError(f"Unknown threshold method: {threshold_method}")

    thr *= threshold_scale

    if background == "brighter":
        background_mask = smooth > thr
    elif background == "darker":
        background_mask = smooth < thr
    else:
        raise ValueError("background must be 'brighter' or 'darker'")

    if opening_radius > 0:
        background_mask = opening(background_mask, disk(opening_radius))

    if closing_radius > 0:
        background_mask = closing(background_mask, disk(closing_radius))

    background_mask = remove_small_objects(
        background_mask.astype(bool),
        min_size=min_object_size,
    )

    mask = ~background_mask
    mask = ndi.binary_fill_holes(mask)
    mask = remove_small_objects(mask.astype(bool), min_size=min_object_size)
    mask = remove_small_holes(mask.astype(bool), area_threshold=min_hole_size)
    mask = keep_largest_object(mask)

    return mask.astype(bool), thr


def bbox_from_mask(mask, padding=500):
    ys, xs = np.where(mask)

    if len(xs) == 0 or len(ys) == 0:
        raise ValueError("No foreground detected. Try changing segmentation settings.")

    ymin, ymax = ys.min(), ys.max() + 1
    xmin, xmax = xs.min(), xs.max() + 1

    ymin = max(0, ymin - padding)
    xmin = max(0, xmin - padding)
    ymax = min(mask.shape[0], ymax + padding)
    xmax = min(mask.shape[1], xmax + padding)

    return ymin, ymax, xmin, xmax


def add_scalebar(ax, img_shape, pixel_size_nm, scalebar_length_nm):
    img_h, img_w = img_shape
    scalebar_length_px = int(round(scalebar_length_nm / pixel_size_nm))
    margin_x = int(img_w * 0.05)
    margin_y = int(img_h * 0.05)
    scalebar_height_px = max(1, min(int(img_h * 0.015), 200))
    fontsize = max(6, int(scalebar_height_px * 0.45))

    x0 = max(0, img_w - margin_x - scalebar_length_px)
    y0 = max(0, img_h - margin_y - scalebar_height_px)

    ax.add_patch(
        Rectangle(
            (x0, y0),
            scalebar_length_px,
            scalebar_height_px,
            facecolor="black",
            edgecolor="black",
        )
    )
    ax.text(
        x0 + scalebar_length_px / 2,
        y0 + scalebar_height_px / 2,
        f"{scalebar_length_nm / 1000:g} um",
        color="white",
        ha="center",
        va="center",
        fontsize=fontsize,
    )


def save_overview_png(img_uint8, voxel_size, png_path, scalebar_length_nm, preview_factor):
    pixel_size_nm = float(voxel_size.x) / 10.0
    preview = img_uint8[::preview_factor, ::preview_factor] if preview_factor > 1 else img_uint8
    preview_pixel_size_nm = pixel_size_nm * preview_factor

    dpi = 50
    fig, ax = plt.subplots(figsize=(preview.shape[1] / dpi, preview.shape[0] / dpi), dpi=dpi)
    ax.imshow(preview, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
    ax.axis("off")
    add_scalebar(ax, preview.shape, preview_pixel_size_nm, scalebar_length_nm)
    plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
    plt.savefig(png_path, dpi=dpi, pad_inches=0)
    plt.close(fig)


def dilate_mask(mask, dilation_fraction):
    if dilation_fraction <= 0:
        return mask

    iterations = int(max(mask.shape) * dilation_fraction)
    if iterations <= 0:
        return mask

    return ndi.binary_dilation(mask, iterations=iterations)


def save_qc_png(
    img_uint8,
    mask,
    final_mask,
    bbox,
    voxel_size,
    out_png,
    scalebar_length_nm,
    preview_factor,
):
    ymin, ymax, xmin, xmax = bbox
    pixel_size_nm = float(voxel_size.x) / 10.0
    preview = img_uint8[::preview_factor, ::preview_factor] if preview_factor > 1 else img_uint8
    mask_preview = mask[::preview_factor, ::preview_factor] if preview_factor > 1 else mask
    preview_pixel_size_nm = pixel_size_nm * preview_factor

    fig, ax = plt.subplots(figsize=(10, 10))
    ax.imshow(preview, cmap="gray", vmin=0, vmax=255)
    ax.contour(mask_preview, levels=[0.5], linewidths=1, colors="magenta")

    final_preview = final_mask[::preview_factor, ::preview_factor] if preview_factor > 1 else final_mask
    ax.contour(final_preview, levels=[0.5], linewidths=1, colors="cyan")

    box_x = [xmin, xmax, xmax, xmin, xmin]
    box_y = [ymin, ymin, ymax, ymax, ymin]
    if preview_factor > 1:
        box_x = [x / preview_factor for x in box_x]
        box_y = [y / preview_factor for y in box_y]
    ax.plot(box_x, box_y, linewidth=2)
    ax.axis("off")
    add_scalebar(ax, preview.shape, preview_pixel_size_nm, scalebar_length_nm)
    plt.tight_layout()
    plt.savefig(out_png, dpi=200)
    plt.close(fig)


def open_zarr_group(path):
    try:
        return zarr.open_group(str(path), mode="w", zarr_format=2)
    except TypeError:
        return zarr.open_group(str(path), mode="w", zarr_version=2)


def save_mask_omezarr(mask, output_path, voxel_size, flip_vertical=False):
    output_path = Path(output_path)
    if output_path.exists():
        shutil.rmtree(output_path)

    root = open_zarr_group(output_path)
    if flip_vertical:
        mask = np.flipud(mask)

    chunks = tuple(min(dim, 2048) for dim in mask.shape)
    mask_data = mask.astype(np.uint8)
    try:
        root.create_array("0", data=mask_data, chunks=chunks, overwrite=True)
    except AttributeError:
        root.create_dataset(
            "0",
            data=mask_data,
            chunks=chunks,
            dtype="uint8",
            overwrite=True,
        )
    except TypeError:
        root.create_dataset(
            "0",
            shape=mask_data.shape,
            data=mask_data,
            chunks=chunks,
            dtype="uint8",
            overwrite=True,
        )
    pixel_size_nm = float(voxel_size.x) / 10.0
    root.attrs["multiscales"] = [
        {
            "version": "0.4",
            "name": output_path.name,
            "axes": [
                {"name": "y", "type": "space", "unit": "nanometer"},
                {"name": "x", "type": "space", "unit": "nanometer"},
            ],
            "datasets": [
                {
                    "path": "0",
                    "coordinateTransformations": [
                        {"type": "scale", "scale": [pixel_size_nm, pixel_size_nm]}
                    ],
                }
            ],
        }
    ]
    root.attrs["omero"] = {
        "channels": [
            {
                "label": "coarse_cell_mask",
                "color": "FF00FF",
                "window": {"start": 0, "end": 1, "min": 0, "max": 1},
                "active": True,
            }
        ]
    }


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create an overview PNG plus optional coarse segmentation outputs from an MRC file."
    )
    parser.add_argument("-i", "--input", required=True, help="Path to input MRC file")
    parser.add_argument("-o", "--output", required=True, help="Path to output overview PNG")
    parser.add_argument("--qc-output", default=None, help="Optional QC PNG with mask contours")
    parser.add_argument("--mask-output", default=None, help="Optional OME-Zarr label mask output")
    parser.add_argument("--scalebar-length-nm", type=float, default=5000)
    parser.add_argument("--preview-factor", type=int, default=4)
    parser.add_argument(
        "--segmentation-mode",
        choices=["foreground", "background_negative"],
        default="foreground",
    )
    parser.add_argument("--foreground", choices=["darker", "brighter"], default="darker")
    parser.add_argument("--threshold", choices=["otsu", "li", "yen"], default="otsu")
    parser.add_argument("--threshold-scale", type=float, default=1.0)
    parser.add_argument("--sigma", type=float, default=5)
    parser.add_argument("--padding", type=int, default=500)
    parser.add_argument("--mask-dilation-fraction", type=float, default=0.2)
    parser.add_argument(
        "--flip-mask-vertical",
        action="store_true",
        help="Flip exported mask vertically to match consumers that display MRC-derived OME-Zarr with inverted y.",
    )
    parser.add_argument("--min-object-size", type=int, default=50000)
    parser.add_argument("--min-hole-size", type=int, default=50000)
    parser.add_argument("--closing-radius", type=int, default=15)
    parser.add_argument("--opening-radius", type=int, default=3)
    return parser.parse_args()


def main():
    args = parse_args()
    img, voxel_size = load_mrc_2d(args.input)
    img_uint8 = normalize_for_display(img)

    print("Original image shape:", img_uint8.shape)
    print("Pixel size:", float(voxel_size.x), "Angstrom =", float(voxel_size.x) / 10.0, "nm")

    save_overview_png(
        img_uint8,
        voxel_size,
        args.output,
        args.scalebar_length_nm,
        max(1, args.preview_factor),
    )
    print("Saved overview PNG:", args.output)

    if args.qc_output or args.mask_output:
        if args.segmentation_mode == "foreground":
            mask, thr = make_mask(
                img,
                foreground=args.foreground,
                sigma=args.sigma,
                threshold_method=args.threshold,
                min_object_size=args.min_object_size,
                min_hole_size=args.min_hole_size,
                closing_radius=args.closing_radius,
                opening_radius=args.opening_radius,
                threshold_scale=args.threshold_scale,
            )
        else:
            mask, thr = make_mask_background_negative(
                img,
                sigma=args.sigma,
                threshold_method=args.threshold,
                min_object_size=args.min_object_size,
                min_hole_size=args.min_hole_size,
                closing_radius=args.closing_radius,
                opening_radius=args.opening_radius,
                threshold_scale=args.threshold_scale,
            )

        final_mask = dilate_mask(mask, args.mask_dilation_fraction)
        bbox = bbox_from_mask(final_mask, padding=args.padding)
        print(f"Threshold: {thr:.4f}")
        print(f"Bounding box: ymin={bbox[0]}, ymax={bbox[1]}, xmin={bbox[2]}, xmax={bbox[3]}")

        if args.qc_output:
            save_qc_png(
                img_uint8,
                mask,
                final_mask,
                bbox,
                voxel_size,
                args.qc_output,
                args.scalebar_length_nm,
                max(1, args.preview_factor),
            )
            print("Saved QC PNG:", args.qc_output)

        if args.mask_output:
            save_mask_omezarr(
                final_mask,
                args.mask_output,
                voxel_size,
                flip_vertical=args.flip_mask_vertical,
            )
            print("Saved mask OME-Zarr:", args.mask_output)


if __name__ == "__main__":
    main()
