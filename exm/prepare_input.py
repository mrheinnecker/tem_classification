import argparse
import json
from pathlib import Path

import numpy as np

try:
    import nd2
except ImportError:  # pragma: no cover - checked at runtime
    nd2 = None


def read_channel_stack(raw_file, channel_in_file):
    """Z/Y/X stack of one channel of an .nd2 file."""
    with nd2.ND2File(raw_file) as handle:
        data = handle.asarray()
        axes = list(handle.sizes)
    if "C" in axes:
        data = np.take(data, channel_in_file, axis=axes.index("C"))
        axes.remove("C")
    if "Z" not in axes:
        data = data[np.newaxis, ...]
    return np.asarray(data)


def channel_stats(stack, index):
    # display range from percentiles of a subsample, robust against hot pixels / empty background
    sample = stack[:, ::4, ::4]
    low, high = np.percentile(sample, [0.1, 99.9])
    return {
        "index": index,
        "min": float(stack.min()),
        "max": float(stack.max()),
        "contrast_limits": f"({float(low):.6g},{float(high):.6g})",
        "display_min": float(low),
        "display_max": float(high),
    }


def ome_tiff_metadata(metadata):
    channels = metadata["channels"]
    ome_metadata = {
        "axes": "CZYX",
        "PhysicalSizeX": float(metadata["x_scale_nm"]),
        "PhysicalSizeXUnit": "nm",
        "PhysicalSizeY": float(metadata["y_scale_nm"]),
        "PhysicalSizeYUnit": "nm",
        "PhysicalSizeZ": float(metadata["z_scale_nm"]),
        "PhysicalSizeZUnit": "nm",
        "Channel": {"Name": [channel["display"] for channel in channels]},
    }
    excitation = [channel.get("excitation_wavelength_nm") for channel in channels]
    emission = [channel.get("emission_wavelength_nm") for channel in channels]
    if all(value is not None for value in excitation):
        ome_metadata["Channel"]["ExcitationWavelength"] = excitation
        ome_metadata["Channel"]["ExcitationWavelengthUnit"] = ["nm"] * len(channels)
    if all(value is not None for value in emission):
        ome_metadata["Channel"]["EmissionWavelength"] = emission
        ome_metadata["Channel"]["EmissionWavelengthUnit"] = ["nm"] * len(channels)
    return ome_metadata


def write_channels_as_ome_tiff(metadata, output_path):
    """Merge the per-channel .nd2 files into one CZYX OME-TIFF, one channel in memory at a time."""
    import tifffile

    size_c, size_z, size_y, size_x = metadata["shape"]
    stats = []

    def planes():
        for channel in metadata["channels"]:
            stack = read_channel_stack(channel["raw_file"], channel["channel_in_file"])
            if stack.shape != (size_z, size_y, size_x):
                raise ValueError(
                    f"{channel['raw_file']}: shape {stack.shape} differs from {(size_z, size_y, size_x)}"
                )
            stats.append(channel_stats(stack, channel["index"]))
            yield from stack
            del stack

    with nd2.ND2File(metadata["channels"][0]["raw_file"]) as handle:
        dtype = handle.dtype
    tifffile.imwrite(
        output_path,
        data=planes(),
        shape=(size_c, size_z, size_y, size_x),
        dtype=dtype,
        bigtiff=True,
        ome=True,
        photometric="minisblack",
        metadata=ome_tiff_metadata(metadata),
    )
    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Merge the per-channel EXM .nd2 files of one dataset into a CZYX OME-TIFF for EuBI-Bridge."
    )
    parser.add_argument("--name", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--prepared-log", required=True)
    args = parser.parse_args()

    if nd2 is None:
        raise RuntimeError("the nd2 python package is required to read .nd2 files")

    metadata_path = Path(args.metadata_json)
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    prepared_path = output_dir / f"{args.name}.ome.tif"
    stats = write_channels_as_ome_tiff(metadata, prepared_path)

    metadata["prepared_input_path"] = str(prepared_path)
    metadata["prepared_input_mode"] = "nd2_channels_to_ome_tiff"
    metadata["channel_stats"] = stats
    stats_by_index = {row["index"]: row for row in stats}
    for channel in metadata["channels"]:
        row = stats_by_index[channel["index"]]
        channel["min"] = row["display_min"]
        channel["max"] = row["display_max"]
        channel["contrast_limits"] = row["contrast_limits"]
    metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")

    with Path(args.prepared_log).open("w", encoding="utf-8") as handle:
        handle.write("name\traw_path\tprepared_path\tmode\tchannels\n")
        handle.write(
            f"{args.name}\t{metadata['raw_path']}\t{prepared_path}\tnd2_channels_to_ome_tiff\t"
            f"{','.join(channel['display'] for channel in metadata['channels'])}\n"
        )


if __name__ == "__main__":
    main()
