#!python

import argparse
import mrcfile
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

# ---------------------------
# Argument parsing
# ---------------------------
parser = argparse.ArgumentParser(description="Convert MRC to PNG with scaling")

parser.add_argument(
    "-i", "--input",
    required=True,
    help="Path to input MRC file"
)

parser.add_argument(
    "-o", "--output",
    required=True,
    help="Path to output PNG file"
)

args = parser.parse_args()

mrc_path = args.input
png_path = args.output

# ---------------------------
# parameters
# ---------------------------
scalebar_length_nm = 5000   # e.g. 100, 200, 500, 1000, 5000

# quick preview mode
preview = True
preview_factor = 4   # 4 means keep every 4th pixel in x and y

# ---------------------------
# read only what is needed
# ---------------------------
with mrcfile.open(mrc_path, permissive=True) as mrc:
    voxel_size = mrc.voxel_size
    data = mrc.data

    # if 2D: use directly
    # if 3D: take middle slice
    if data.ndim == 2:
        img = np.array(data, dtype=np.float32, copy=False)
    elif data.ndim == 3:
        img = np.array(data[data.shape[0] // 2, :, :], dtype=np.float32, copy=False)
    else:
        raise ValueError(f"Unsupported data dimensions: {data.shape}")

# ---------------------------
# autoscale grey values with percentile clipping
# ---------------------------
p1, p99 = np.percentile(img, (1, 99))

if p99 > p1:
    np.clip(img, p1, p99, out=img)
    img -= p1
    img /= (p99 - p1)
else:
    img.fill(0)

img *= 255.0
img_uint8 = img.astype(np.uint8)
del img

# ---------------------------
# get pixel size
# ---------------------------
# mrc voxel_size is usually in Angstrom
pixel_size_angstrom = float(voxel_size.x)
pixel_size_nm = pixel_size_angstrom / 10.0

print("Original image shape:", img_uint8.shape)
print("Pixel size:", pixel_size_angstrom, "Å =", pixel_size_nm, "nm")

# convert desired scalebar length to pixels
scalebar_length_px = int(round(scalebar_length_nm / pixel_size_nm))

# ---------------------------
# dynamic geometry
# ---------------------------
img_h, img_w = img_uint8.shape

# margins: 5% of image size
margin_x = int(img_w * 0.05)
margin_y = int(img_h * 0.05)

# dynamic scalebar thickness: 1.5% of image height
scalebar_height_px = max(8, min(int(img_h * 0.015), 200))

# dynamic font size based on scalebar height
fontsize = max(8, int(scalebar_height_px * 0.45))

# ---------------------------
# quick preview downscaling
# ---------------------------
if preview and preview_factor > 1:
    img_uint8 = img_uint8[::preview_factor, ::preview_factor]

    scalebar_length_px = max(1, int(round(scalebar_length_px / preview_factor)))
    scalebar_height_px = max(1, int(round(scalebar_height_px / preview_factor)))
    margin_x = int(round(margin_x / preview_factor))
    margin_y = int(round(margin_y / preview_factor))
    fontsize = max(6, int(round(fontsize / preview_factor)))

    print("Preview image shape:", img_uint8.shape)
    print(f"Preview mode active: downscaled by factor {preview_factor}")

# update image size after optional downscaling
img_h, img_w = img_uint8.shape

# bottom-right position
x0 = img_w - margin_x - scalebar_length_px
y0 = img_h - margin_y - scalebar_height_px

# keep bar inside image if it becomes too long
x0 = max(0, x0)
y0 = max(0, y0)

# ---------------------------
# plot
# ---------------------------
dpi = 50
fig_w = img_w / dpi
fig_h = img_h / dpi

fig, ax = plt.subplots(figsize=(fig_w, fig_h), dpi=dpi)
ax.imshow(img_uint8, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
ax.axis("off")

# add black scalebar
rect = Rectangle(
    (x0, y0),
    scalebar_length_px,
    scalebar_height_px,
    facecolor="black",
    edgecolor="black"
)
ax.add_patch(rect)

# add centered label on the scalebar
ax.text(
    x0 + scalebar_length_px / 2,
    y0 + scalebar_height_px / 2,
    f"{scalebar_length_nm/1000:g} µm",
    color="white",
    ha="center",
    va="center",
    fontsize=fontsize
)

plt.subplots_adjust(left=0, right=1, top=1, bottom=0)
plt.savefig(png_path, dpi=dpi, pad_inches=0)
plt.close(fig)

print("Saved:", png_path)
