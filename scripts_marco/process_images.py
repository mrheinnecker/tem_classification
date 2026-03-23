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
# parameters
scalebar_length_nm = 5000   # change as needed, e.g. 100, 200, 500, 1000
scalebar_height_px = 150
margin_px = 30
label_offset_px = 120

with mrcfile.open(mrc_path) as mrc:
    data = mrc.data.copy()
    voxel_size = mrc.voxel_size

# -----------------------------
# choose image to export
# -----------------------------
# if 2D: use directly
# if 3D: take middle slice
if data.ndim == 2:
    img = data
elif data.ndim == 3:
    img = data[data.shape[0] // 2, :, :]
else:
    raise ValueError(f"Unsupported data dimensions: {data.shape}")

# -----------------------------
# autoscale grey values to min/max
# -----------------------------
img = img.astype(np.float32)
img_min = np.min(img)
img_max = np.max(img)


p1, p99 = np.percentile(img, (1, 99))
img_clipped = np.clip(img, p1, p99)
img_scaled = (img_clipped - p1) / (p99 - p1)

img_uint8 = (img_scaled * 255).round().astype(np.uint8)

fig, ax = plt.subplots(figsize=(10, 10))
ax.imshow(img_uint8, cmap="gray", vmin=0, vmax=255, interpolation="nearest")
ax.axis("off")
# -----------------------------
# get pixel size
# -----------------------------
# mrc voxel_size is usually in Angstrom
pixel_size_angstrom = float(voxel_size.x)
pixel_size_nm = pixel_size_angstrom / 10.0

print("Image shape:", img.shape)
print("Pixel size:", pixel_size_angstrom, "Å =", pixel_size_nm, "nm")

# convert desired scalebar length to pixels
scalebar_length_px = scalebar_length_nm / pixel_size_nm
scalebar_length_px = int(round(scalebar_length_px))

# bottom left position
x0 = margin_px
y0 = img.shape[0] - margin_px - scalebar_height_px


# -----------------------------
# dynamic margins (5% of image size)
# -----------------------------
margin_x = int(img.shape[1] * 0.05)
margin_y = int(img.shape[0] * 0.05)

# bottom-right position
x0 = img.shape[1] - margin_x - scalebar_length_px
y0 = img.shape[0] - margin_y - scalebar_height_px

# add white scalebar
rect = Rectangle(
    (x0, y0),
    scalebar_length_px,
    scalebar_height_px,
    facecolor="white",
    edgecolor="white"
)
ax.add_patch(rect)

# add label BELOW the bar
ax.text(
    x0 + scalebar_length_px / 2,
    y0 + scalebar_height_px + label_offset_px,
    f"{scalebar_length_nm/1000} µm",
    color="white",
    ha="center",
    va="top",
    fontsize=14
)
plt.tight_layout(pad=0)
plt.savefig(png_path, dpi=600, bbox_inches="tight", pad_inches=0)
plt.close()
## test
print("Saved:", png_path)
