#!/usr/bin/env python3

import argparse
import shutil
from pathlib import Path

import numpy as np
import zarr
from scipy import ndimage as ndi
from skimage.filters import threshold_otsu, threshold_li, threshold_yen
from skimage.morphology import (
    remove_small_objects,
    remove_small_holes,
    closing,
    opening,
    disk,
)
from skimage.morphology import dilation
from skimage.measure import label, regionprops
import matplotlib.pyplot as plt


def find_image_array(zarr_root):
    """
    Try to find the main image array in an OME-Zarr.
    Common locations are:
      0
      s0
      scale0/image
    """
    candidates = ["0", "s0", "scale0/image"]

    for c in candidates:
        try:
            arr = zarr_root[c]
            if hasattr(arr, "shape"):
                return c, arr
        except Exception:
            pass

    # fallback: find first array-like child
    def walk(group, prefix=""):
        for key, value in group.items():
            path = f"{prefix}/{key}".strip("/")
            if hasattr(value, "shape"):
                return path, value
            if isinstance(value, zarr.Group):
                found = walk(value, path)
                if found:
                    return found
        return None

    found = walk(zarr_root)
    if found is None:
        raise ValueError("Could not find image array inside OME-Zarr.")
    return found


def squeeze_to_2d(img):
    """
    Converts common OME-Zarr shapes like:
      y, x
      1, y, x
      1, 1, y, x
      1, 1, 1, y, x
    into a 2D image.
    """
    img = np.asarray(img)

    while img.ndim > 2:
        if img.shape[0] == 1:
            img = img[0]
        else:
            raise ValueError(
                f"Image has shape {img.shape}. "
                "Please select one channel/time/z plane first."
            )

    return img


def normalize_for_segmentation(img, p_low=1, p_high=99):
    img = img.astype(np.float32)

    lo = np.percentile(img, p_low)
    hi = np.percentile(img, p_high)

    if hi <= lo:
        raise ValueError("Image has almost no intensity variation.")

    img = (img - lo) / (hi - lo)
    img = np.clip(img, 0, 1)

    return img


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

    return mask.astype(bool), smooth, thr


def bbox_from_mask(mask, padding=500):
    ys, xs = np.where(mask)

    if len(xs) == 0 or len(ys) == 0:
        raise ValueError("No foreground detected. Try changing --foreground or threshold settings.")

    ymin, ymax = ys.min(), ys.max() + 1
    xmin, xmax = xs.min(), xs.max() + 1

    ymin = max(0, ymin - padding)
    xmin = max(0, xmin - padding)
    ymax = min(mask.shape[0], ymax + padding)
    xmax = min(mask.shape[1], xmax + padding)

    return ymin, ymax, xmin, xmax


def save_qc_png(img, mask, bbox, out_png):
    ymin, ymax, xmin, xmax = bbox

    norm = normalize_for_segmentation(img)

    plt.figure(figsize=(10, 10))
    plt.imshow(norm, cmap="gray")
    # original segmentation (purple)
    plt.contour(
        mask,
        levels=[0.5],
        linewidths=1,
        colors="magenta",
    )
    
    # dilated segmentation (red)
    dilation_size = int(max(mask.shape) * 0.05)
    
    dilated_mask = ndi.binary_dilation(
        mask,
        iterations=dilation_size
    )
    
    plt.contour(
        dilated_mask,
        levels=[0.5],
        linewidths=1,
        colors="red",
    )
    plt.plot(
        [xmin, xmax, xmax, xmin, xmin],
        [ymin, ymin, ymax, ymax, ymin],
        linewidth=2,
    )
    plt.axis("off")
    plt.tight_layout()
    plt.savefig(out_png, dpi=200)
    plt.close()


def copy_and_crop_omezarr(input_path, output_path, array_path, bbox):
    """
    Simple conservative approach:
    copy full OME-Zarr folder, then replace the main image array
    with the cropped version.

    This keeps most metadata, but for fully strict OME-NGFF metadata,
    coordinate transforms may need updating later.
    """
    input_path = Path(input_path)
    output_path = Path(output_path)

    if output_path.exists():
        shutil.rmtree(output_path)

    shutil.copytree(input_path, output_path)

    root = zarr.open(str(output_path), mode="a")
    arr = root[array_path]

    data = np.asarray(arr)
    ymin, ymax, xmin, xmax = bbox

    if data.ndim == 2:
        cropped = data[ymin:ymax, xmin:xmax]
    elif data.ndim == 3:
        cropped = data[:, ymin:ymax, xmin:xmax]
    elif data.ndim == 4:
        cropped = data[:, :, ymin:ymax, xmin:xmax]
    elif data.ndim == 5:
        cropped = data[:, :, :, ymin:ymax, xmin:xmax]
    else:
        raise ValueError(f"Unsupported image dimensionality: {data.shape}")

    parent_path = "/".join(array_path.split("/")[:-1])
    array_name = array_path.split("/")[-1]

    parent = root
    if parent_path:
        parent = root[parent_path]

    del parent[array_name]

    new_arr = parent.create_array(
        array_name,
        shape=cropped.shape,
        chunks=arr.chunks if arr.chunks is not None else True,
        dtype=cropped.dtype,
        overwrite=True,
    )
    
    new_arr[:] = cropped

    return cropped.shape
  
def keep_largest_object(mask):
    lab = label(mask)

    regions = regionprops(lab)
    if len(regions) == 0:
        raise ValueError("No foreground objects found after segmentation.")

    largest = max(regions, key=lambda r: r.area)

    clean_mask = lab == largest.label

    return clean_mask
  
  
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
    thr = thr * threshold_scale
    # segment background first
    if background == "brighter":
        background_mask = smooth > thr
    elif background == "darker":
        background_mask = smooth < thr
    else:
        raise ValueError("background must be 'brighter' or 'darker'")

    # clean background
    if opening_radius > 0:
        background_mask = opening(background_mask, disk(opening_radius))

    if closing_radius > 0:
        background_mask = closing(background_mask, disk(closing_radius))

    background_mask = remove_small_objects(
        background_mask.astype(bool),
        min_size=min_object_size,
    )

    # now invert: everything that is not background is cell/object
    mask = ~background_mask

    # clean object mask
    mask = ndi.binary_fill_holes(mask)
    mask = remove_small_objects(mask.astype(bool), min_size=min_object_size)
    mask = remove_small_holes(mask.astype(bool), area_threshold=min_hole_size)

    # keep largest object only
    mask = keep_largest_object(mask)

    return mask.astype(bool), smooth, thr
  
def main():
    parser = argparse.ArgumentParser(
        description="Simple foreground segmentation and cropping for 2D TEM OME-Zarr images."
    )

    parser.add_argument("--input", required=True, help="Input .ome.zarr directory")
    parser.add_argument("--output", required=True, help="Output cropped .ome.zarr directory")

    parser.add_argument(
        "--foreground",
        choices=["darker", "brighter"],
        default="darker",
        help="Whether the cell/foreground is darker or brighter than background",
    )

    parser.add_argument(
        "--threshold",
        choices=["otsu", "li", "yen"],
        default="otsu",
        help="Threshold method",
    )
    parser.add_argument(
        "--segmentation-mode",
        choices=["foreground", "background_negative"],
        default="foreground",
        help="foreground = segment cell directly; background_negative = segment background and invert it",
    )
    parser.add_argument(
        "--threshold-scale",
        type=float,
        default=1.0,
        help="Scale automatic threshold. For brighter background, lower values include lighter cell wall as foreground.",
    )
    parser.add_argument("--sigma", type=float, default=5)
    parser.add_argument("--padding", type=int, default=500)
    parser.add_argument("--min-object-size", type=int, default=50000)
    parser.add_argument("--min-hole-size", type=int, default=50000)
    parser.add_argument("--closing-radius", type=int, default=15)
    parser.add_argument("--opening-radius", type=int, default=3)

    parser.add_argument("--save-mask", action="store_true")
    parser.add_argument("--qc-png", default=None)

    args = parser.parse_args()

    root = zarr.open(str(args.input), mode="r")
    array_path, arr = find_image_array(root)

    print(f"Found image array: {array_path}")
    print(f"Original shape: {arr.shape}")

    img2d = squeeze_to_2d(arr)

    if args.segmentation_mode == "foreground":
        mask, smooth, thr = make_mask(
            img2d,
            foreground=args.foreground,
            sigma=args.sigma,
            threshold_method=args.threshold,
            min_object_size=args.min_object_size,
            min_hole_size=args.min_hole_size,
            closing_radius=args.closing_radius,
            opening_radius=args.opening_radius,
            threshold_scale=args.threshold_scale,
        )
    
    elif args.segmentation_mode == "background_negative":
        mask, smooth, thr = make_mask_background_negative(
            img2d,
            background="brighter",
            sigma=args.sigma,
            threshold_method=args.threshold,
            min_object_size=args.min_object_size,
            min_hole_size=args.min_hole_size,
            closing_radius=args.closing_radius,
            opening_radius=args.opening_radius,
            threshold_scale=args.threshold_scale,
        )

    bbox = bbox_from_mask(mask, padding=args.padding)
    ymin, ymax, xmin, xmax = bbox

    print(f"Threshold: {thr:.4f}")
    print(f"Bounding box: ymin={ymin}, ymax={ymax}, xmin={xmin}, xmax={xmax}")
    print(f"Cropped size: y={ymax-ymin}, x={xmax-xmin}")

    cropped_shape = copy_and_crop_omezarr(
        input_path=args.input,
        output_path=args.output,
        array_path=array_path,
        bbox=bbox,
    )

    print(f"Output shape: {cropped_shape}")
    print(f"Written: {args.output}")

    if args.save_mask:
        mask_out = Path(args.output).with_suffix("").as_posix() + "_mask.npy"
        np.save(mask_out, mask)
        print(f"Saved mask: {mask_out}")

    if args.qc_png is not None:
        save_qc_png(img2d, mask, bbox, args.qc_png)
        print(f"Saved QC PNG: {args.qc_png}")


if __name__ == "__main__":
    main()
