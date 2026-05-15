#!/usr/bin/env python3
import math
import pandas as pd
import mrcfile
import numpy as np
import matplotlib.pyplot as plt


df_in = pd.read_csv("/scratch/rheinnec/viktoria_figure/df_in_full_new.tsv", sep="\t")

out_file = "/scratch/rheinnec/viktoria_figure/figure_2x2_cropped_scalebar_real_imgs_new.png"




def choose_scale_bar_nm(
    img,
    pixel_size_nm,
    start_nm=500,
    min_frac=0.15,
    max_frac=0.35
):
    img_h, img_w = img.shape

    scale_bar_nm = start_nm

    while True:
        scale_bar_px = scale_bar_nm / pixel_size_nm
        frac = scale_bar_px / img_w

        if frac < min_frac:
            scale_bar_nm *= 2
        elif frac > max_frac:
            scale_bar_nm /= 2
            break
        else:
            break

    return scale_bar_nm




def add_scale_bar(
    ax,
    img,
    pixel_size_nm,
    scale_bar_nm=500,
    bar_height_frac=0.012,
    margin_frac=0.04,
    color="black",
    fontsize=14
):
    img_h, img_w = img.shape

    scale_bar_px = scale_bar_nm / pixel_size_nm

    bar_height_px = img_h * bar_height_frac
    margin_px = img_w * margin_frac

    x_start = img_w - scale_bar_px - margin_px
    x_end = img_w - margin_px

    y_start = img_h - margin_px
    y_end = y_start - bar_height_px

    ax.fill_between(
        [x_start, x_end],
        y_start,
        y_end,
        color=color
    )

    ax.text(
        (x_start + x_end) / 2,
        y_end - img_h * 0.015,
        f"{scale_bar_nm} nm",
        color=color,
        fontsize=fontsize,
        ha="center",
        va="bottom"
    )

def load_mrc_image(path):
    with mrcfile.open(path, permissive=True) as mrc:
        img = np.array(mrc.data)   # important: make real copy

    if img.ndim == 3:
        img = img[0, :, :]

    return img


def crop_square(img, start_x, start_y, width, y_origin="bottom"):
    start_x = int(start_x)
    start_y = int(start_y)
    width = int(width)

    img_h, img_w = img.shape

    if y_origin == "bottom":
        start_y = img_h - start_y - width
    elif y_origin == "top":
        start_y = start_y
    else:
        raise ValueError("y_origin must be either 'top' or 'bottom'")

    end_x = start_x + width
    end_y = start_y + width

    return img[start_y:end_y, start_x:end_x]

n_panels = len(df_in)
ncols = 4
nrows = math.ceil(n_panels / ncols)

fig, axes = plt.subplots(
    nrows=nrows,
    ncols=ncols,
    figsize=(4 * ncols, 4 * nrows),
    constrained_layout=True
)

axes = np.array(axes).ravel()

for ax, (_, row) in zip(axes, df_in.iterrows()):
    img = load_mrc_image(row["file"])

    img_crop = crop_square(
        img,
        row["start_x"],
        row["start_y"],
        row["width"],
        y_origin="bottom"
    )

    print("\nPanel", row["label"])
    print("full image shape:", img.shape)
    print("crop shape:", img_crop.shape)
    print("crop min/max:", np.min(img_crop), np.max(img_crop))
    print("crop percentiles:", np.percentile(img_crop, [0.5, 1, 50, 99, 99.5]))

    # robust contrast normalization
    vmin, vmax = np.percentile(img_crop, [1, 99])

    ax.imshow(
        img_crop,
        cmap="gray",
        vmin=vmin,
        vmax=vmax
    )
    add_scale_bar(
        ax=ax,
        img=img_crop,
        pixel_size_nm=1.76,
        scale_bar_nm=500,
        bar_height_frac=0.012,
        margin_frac=0.04
    )
    ax.set_axis_off()

    ax.text(
        0.03, 0.95,
        row["label"],
        transform=ax.transAxes,
        fontsize=20,
        fontweight="bold",
        color="black",
        va="top",
        ha="left"
    )

for ax in axes[len(df_in):]:
    ax.set_axis_off()

plt.savefig(out_file, dpi=300, bbox_inches="tight")
plt.close()

print(f"\nSaved figure to: {out_file}")
