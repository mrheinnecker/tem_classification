import argparse
import json
import re
from pathlib import Path

try:
    import nd2
except ImportError:  # pragma: no cover - checked at runtime
    nd2 = None


# named colors understood by MoBIE / the collection table
NAMED_COLORS = {
    "red": (255, 0, 0),
    "green": (0, 255, 0),
    "blue": (0, 0, 255),
    "yellow": (255, 255, 0),
    "magenta": (255, 0, 255),
    "cyan": (0, 255, 255),
    "white": (255, 255, 255),
}


def parse_optional_float(value):
    if value is None or str(value).strip() in {"", "NA", "nan", "None"}:
        return None
    return float(value)


def to_nm(value, unit):
    if value is None:
        return None
    factors = {"nm": 1.0, "um": 1000.0, "µm": 1000.0, "micron": 1000.0, "mm": 1_000_000.0}
    unit = (unit or "nm").strip().lower()
    if unit not in factors:
        raise ValueError(f"Unsupported scale unit: {unit}")
    return value * factors[unit]


def nearest_named_color(color):
    """Nikon channel color (r, g, b) -> closest named color."""
    if color is None:
        return None
    rgb = (color.r, color.g, color.b)
    return min(
        NAMED_COLORS,
        key=lambda name: sum((a - b) ** 2 for a, b in zip(NAMED_COLORS[name], rgb)),
    )


def channel_display(name):
    """'Cy5 (Single EM)' -> 'Cy5'"""
    display = re.sub(r"\s*\(.*?\)\s*", " ", name or "").strip()
    display = re.sub(r"[^A-Za-z0-9]+", "_", display).strip("_")
    return display or None


def read_nd2_file(path):
    """Shape, voxel size, channels and acquisition info of one .nd2 file."""
    with nd2.ND2File(path) as handle:
        sizes = dict(handle.sizes)
        voxel = handle.voxel_size()
        metadata = handle.metadata
        text_info = dict(handle.text_info)

        channels = []
        for channel in metadata.channels or []:
            info = channel.channel
            microscope = channel.microscope
            channels.append(
                {
                    "label": info.name,
                    "display": channel_display(info.name),
                    "color": nearest_named_color(info.color),
                    "nikon_color_rgb": [info.color.r, info.color.g, info.color.b] if info.color else None,
                    "excitation_wavelength_nm": info.excitationLambdaNm,
                    "emission_wavelength_nm": info.emissionLambdaNm,
                    "objective": microscope.objectiveName,
                    "objective_magnification": microscope.objectiveMagnification,
                    "objective_na": microscope.objectiveNumericalAperture,
                    "immersion_refractive_index": microscope.immersionRefractiveIndex,
                    "modality": list(microscope.modalityFlags or []),
                }
            )

        stage_position = None
        try:
            position = handle.frame_metadata(0).channels[0].position.stagePositionUm
            stage_position = {"x": position.x, "y": position.y, "z": position.z}
        except Exception:
            pass

    return {
        "raw_file": str(path),
        "sizes": sizes,
        "x_scale_nm": voxel.x * 1000.0 if voxel.x else None,
        "y_scale_nm": voxel.y * 1000.0 if voxel.y else None,
        "z_scale_nm": voxel.z * 1000.0 if voxel.z else None,
        "channels": channels,
        "acquisition_date": text_info.get("date"),
        "optics": text_info.get("optics"),
        "capturing": text_info.get("capturing"),
        "stage_position_um": stage_position,
        "text_info": text_info,
    }


def same_value(values, key, tolerance=1e-6):
    values = [value for value in values if value is not None]
    if not values:
        return None
    first = values[0]
    if any(abs(value - first) > tolerance * max(abs(first), 1.0) for value in values):
        raise ValueError(f"Channel files have different {key}: {values}")
    return first


def extract_dataset_metadata(raw_files):
    """One dataset = one or more .nd2 files (one per channel) with identical X/Y/Z."""
    files = [read_nd2_file(path) for path in raw_files]

    for entry in files:
        if "T" in entry["sizes"] or "P" in entry["sizes"]:
            raise ValueError(
                f"{entry['raw_file']} has a time or position axis {entry['sizes']}; only single z-stacks are supported"
            )

    shapes = {tuple(entry["sizes"].get(axis, 1) for axis in "ZYX") for entry in files}
    if len(shapes) != 1:
        raise ValueError(f"Channel files have different Z/Y/X shapes: {sorted(shapes)}")
    size_z, size_y, size_x = shapes.pop()

    channels = []
    for entry in files:
        n_channels = entry["sizes"].get("C", 1)
        file_channels = entry["channels"] or [{"label": None, "display": None, "color": None}]
        for channel_in_file in range(n_channels):
            channel = dict(file_channels[min(channel_in_file, len(file_channels) - 1)])
            channel["raw_file"] = entry["raw_file"]
            channel["channel_in_file"] = channel_in_file
            channels.append(channel)

    # order channels by excitation wavelength (DAPI, FITC, TRITC, Cy5, ...)
    channels.sort(key=lambda channel: (channel.get("excitation_wavelength_nm") is None, channel.get("excitation_wavelength_nm") or 0))
    used_displays = set()
    for index, channel in enumerate(channels):
        channel["index"] = index
        display = channel.get("display") or f"channel_{index}"
        if display in used_displays:
            display = f"{display}_{index}"
        used_displays.add(display)
        channel["display"] = display
        channel["label"] = channel.get("label") or display
        channel["color"] = channel.get("color") or "white"

    first = files[0]
    return {
        "source_suffix": ".nd2",
        "raw_files": [entry["raw_file"] for entry in files],
        "x_scale_nm": same_value([entry["x_scale_nm"] for entry in files], "x pixel size"),
        "y_scale_nm": same_value([entry["y_scale_nm"] for entry in files], "y pixel size"),
        "z_scale_nm": same_value([entry["z_scale_nm"] for entry in files], "z spacing"),
        "shape": [len(channels), size_z, size_y, size_x],
        "axes": "CZYX",
        "size_c": len(channels),
        "channels": channels,
        "acquisition_date": first["acquisition_date"],
        "objective": (first["channels"] or [{}])[0].get("objective"),
        "stage_position_um": first["stage_position_um"],
    }, files


def merge_overrides(metadata, args):
    overrides = {
        "x_scale_nm": to_nm(parse_optional_float(args.x_scale), args.scale_unit),
        "y_scale_nm": to_nm(parse_optional_float(args.y_scale), args.scale_unit),
        "z_scale_nm": to_nm(parse_optional_float(args.z_scale), args.scale_unit),
    }
    for key, value in overrides.items():
        if value is not None:
            metadata[f"{key}_from_file"] = metadata.get(key)
            metadata[key] = value
    return metadata


def main():
    parser = argparse.ArgumentParser(
        description="Extract EXM (Nikon .nd2, one file per channel) pixel size and channel metadata."
    )
    parser.add_argument("--input", required=True, help="';'-separated list of .nd2 files of one dataset")
    parser.add_argument("--name", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--pixel-size-tsv", required=True)
    parser.add_argument("--raw-metadata-json", required=True, help="full per-file metadata (text_info etc.)")
    parser.add_argument("--x-scale", default="")
    parser.add_argument("--y-scale", default="")
    parser.add_argument("--z-scale", default="")
    parser.add_argument("--scale-unit", default="nm")
    args = parser.parse_args()

    if nd2 is None:
        raise RuntimeError("the nd2 python package is required to read .nd2 files")

    raw_files = [Path(path) for path in args.input.split(";") if path.strip()]
    missing_files = [str(path) for path in raw_files if not path.exists()]
    if missing_files:
        raise FileNotFoundError(f"Raw image(s) do not exist: {missing_files}")

    dataset_metadata, file_metadata = extract_dataset_metadata(raw_files)
    metadata = {"name": args.name, "raw_path": args.input}
    metadata.update(dataset_metadata)
    metadata = merge_overrides(metadata, args)

    missing = [key for key in ("x_scale_nm", "y_scale_nm", "z_scale_nm") if metadata.get(key) is None]
    if missing:
        raise ValueError(
            "Missing required scale metadata "
            + ", ".join(missing)
            + ". Provide sheet columns/launcher defaults."
        )

    Path(args.metadata_json).write_text(json.dumps(metadata, indent=2, sort_keys=True, default=str), encoding="utf-8")
    Path(args.raw_metadata_json).write_text(json.dumps(file_metadata, indent=2, sort_keys=True, default=str), encoding="utf-8")
    with Path(args.pixel_size_tsv).open("w", encoding="utf-8") as handle:
        handle.write("x_nm\ty_nm\tz_nm\n")
        handle.write(f"{metadata['x_scale_nm']}\t{metadata['y_scale_nm']}\t{metadata['z_scale_nm']}\n")


if __name__ == "__main__":
    main()
