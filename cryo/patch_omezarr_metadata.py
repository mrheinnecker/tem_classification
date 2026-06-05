import argparse
import json
from pathlib import Path


COLOR_TO_HEX = {
    "red": "FF0000",
    "green": "00FF00",
    "blue": "0000FF",
    "yellow": "FFFF00",
    "magenta": "FF00FF",
    "cyan": "00FFFF",
    "white": "FFFFFF",
    "gray": "FFFFFF",
    "grey": "FFFFFF",
}


def find_zarr_root(path):
    root = Path(path)
    if (root / ".zattrs").exists() or (root / ".zgroup").exists():
        return root

    for candidate in root.rglob("*"):
        if candidate.is_dir() and candidate.suffix in {".zarr", ".ome.zarr"}:
            if (candidate / ".zattrs").exists() or (candidate / ".zgroup").exists():
                return candidate
    raise FileNotFoundError(f"Could not find OME-Zarr root below {root}")


def parse_contrast_limits(value):
    if not value:
        return None, None
    value = str(value).strip().strip("()")
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 2:
        return None, None
    try:
        return float(parts[0]), float(parts[1])
    except ValueError:
        return None, None


def channel_color(channel):
    color = str(channel.get("color", "")).strip()
    return COLOR_TO_HEX.get(color.lower(), "FFFFFF")


def build_omero_channels(metadata):
    channels = []
    for index, channel in enumerate(metadata.get("channels", [])):
        min_value = channel.get("min")
        max_value = channel.get("max")
        if min_value is None or max_value is None:
            min_value, max_value = parse_contrast_limits(channel.get("contrast_limits"))
        if min_value is None:
            min_value = 0.0
        if max_value is None:
            max_value = 1.0

        label = (
            channel.get("display")
            or channel.get("label")
            or f"channel_{channel.get('index', index)}"
        )
        channels.append(
            {
                "active": True,
                "coefficient": 1,
                "color": channel_color(channel),
                "family": "linear",
                "inverted": False,
                "label": str(label),
                "window": {
                    "start": min_value,
                    "end": max_value,
                    "min": min_value,
                    "max": max_value,
                },
            }
        )
    return channels


def compact_cryo_metadata(metadata):
    keys = [
        "name",
        "raw_path",
        "source_suffix",
        "x_scale_nm",
        "y_scale_nm",
        "z_scale_nm",
        "size_c",
        "channels",
        "channel_stats",
        "prepared_input_mode",
    ]
    return {key: metadata[key] for key in keys if key in metadata}


def main():
    parser = argparse.ArgumentParser(
        description="Patch extracted CRYO/CZI metadata into an OME-Zarr .zattrs file."
    )
    parser.add_argument("--omezarr", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--log", required=True)
    args = parser.parse_args()

    zarr_root = find_zarr_root(args.omezarr)
    zattrs_path = zarr_root / ".zattrs"
    attrs = {}
    if zattrs_path.exists():
        attrs = json.loads(zattrs_path.read_text(encoding="utf-8"))

    metadata = json.loads(Path(args.metadata_json).read_text(encoding="utf-8"))
    omero_channels = build_omero_channels(metadata)
    if omero_channels:
        omero = attrs.get("omero", {})
        omero["channels"] = omero_channels
        omero.setdefault("rdefs", {})["model"] = "color"
        attrs["omero"] = omero

    attrs["cryo_metadata"] = compact_cryo_metadata(metadata)
    zattrs_path.write_text(json.dumps(attrs, indent=2, sort_keys=True), encoding="utf-8")

    with Path(args.log).open("w", encoding="utf-8") as handle:
        handle.write("omezarr\tmetadata_json\tpatched_zattrs\tchannels\n")
        handle.write(f"{zarr_root}\t{args.metadata_json}\t{zattrs_path}\t{len(omero_channels)}\n")


if __name__ == "__main__":
    main()
