import tifffile
import json

infile = "/g/schwab/marco/tiftest/ATH_20240701_PM_104.tif"
outfile = "/g/schwab/marco/tiftest/metadata.json"

metadata = {}

with tifffile.TiffFile(infile) as tif:

    # basic TIFF tags
    tags = {}
    for tag in tif.pages[0].tags.values():
        try:
            tags[tag.name] = str(tag.value)
        except Exception:
            tags[tag.name] = "UNREADABLE"

    metadata["tiff_tags"] = tags

    # OME metadata
    metadata["ome_metadata"] = tif.ome_metadata

    # ImageJ metadata
    metadata["imagej_metadata"] = tif.imagej_metadata

    # series information
    metadata["series"] = [
        {
            "shape": str(series.shape),
            "dtype": str(series.dtype),
            "axes": str(series.axes)
        }
        for series in tif.series
    ]

# save as JSON
with open(outfile, "w") as f:
    json.dump(metadata, f, indent=2)

print(f"Saved metadata to: {outfile}")
