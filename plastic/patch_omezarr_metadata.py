import argparse
import json
import xml.etree.ElementTree as ET
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
def compact_label(value):
    return "".join(char for char in str(value or "").lower() if char.isalnum())


def rounded_wavelength(channel, key):
    value = channel.get(key)
    if value is None:
        return None
    try:
        return round(float(value))
    except (TypeError, ValueError):
        return None


def channel_matches(channel, label):
    label_compact = compact_label(label)
    display = compact_label(channel.get("display"))
    channel_label = compact_label(channel.get("label"))
    fluor = compact_label(channel.get("fluor"))
    excitation = rounded_wavelength(channel, "excitation_wavelength_nm")
    emission = rounded_wavelength(channel, "emission_wavelength_nm")

    if label == "GFP":
        return (
            label_compact in {display, channel_label}
            or "egfp" in fluor
            or excitation == 488
            or emission == 509
        )
    if label == "PE":
        return (
            label_compact in {display, channel_label}
            or "alexafluor555" in fluor
            or "af555" in fluor
            or excitation == 553
            or emission == 568
        )
    if label == "ChloA":
        return (
            label_compact in {display, channel_label}
            or "chlorophylla" in fluor
            or excitation == 655
            or emission == 667
        )
    if label == "TL":
        return label_compact in {display, channel_label}
    return label_compact in display or label_compact in channel_label


def real_channels_only(metadata):
    channels = metadata.get("channels", [])
    normalized = []
    for index, channel in enumerate(channels):
        row = dict(channel)
        row["index"] = index
        normalized.append(row)
    return normalized


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
    for index, channel in enumerate(real_channels_only(metadata)):
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


def compact_plastic_metadata(metadata):
    compact = dict(metadata)
    if "channels" in compact:
        compact["channels"] = real_channels_only(metadata)
        compact["size_c"] = len(compact["channels"])
    return compact


def xml_local_name(element):
    return str(element.tag).split("}", 1)[-1]


def format_ome_float(value):
    return f"{float(value):g}"


def patch_channel_attribute(element, attribute, value):
    if value is None:
        element.attrib.pop(attribute, None)
        return
    element.set(attribute, format_ome_float(value))


def patch_ome_xml_file(path, metadata):
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return False

    root = tree.getroot()
    namespace = ""
    if root.tag.startswith("{"):
        namespace = root.tag.split("}", 1)[0][1:]
        ET.register_namespace("", namespace)

    channels = real_channels_only(metadata)
    if not channels:
        return False

    channel_elements = [
        element
        for element in root.iter()
        if xml_local_name(element) == "Channel"
    ]
    if not channel_elements:
        return False

    for index, element in enumerate(channel_elements[: len(channels)]):
        channel = channels[index]
        label = channel.get("display") or channel.get("label")
        fluor = channel.get("fluor")
        if label:
            element.set("Name", str(label))
        if fluor:
            element.set("Fluor", str(fluor))
        else:
            element.attrib.pop("Fluor", None)

        excitation = channel.get("excitation_wavelength_nm")
        emission = channel.get("emission_wavelength_nm")
        patch_channel_attribute(element, "ExcitationWavelength", excitation)
        patch_channel_attribute(element, "EmissionWavelength", emission)
        if excitation is None:
            element.attrib.pop("ExcitationWavelengthUnit", None)
        else:
            element.set("ExcitationWavelengthUnit", "nm")
        if emission is None:
            element.attrib.pop("EmissionWavelengthUnit", None)
        else:
            element.set("EmissionWavelengthUnit", "nm")

    tree.write(path, encoding="utf-8", xml_declaration=True)
    return True


def patch_ome_xml_files(zarr_root, metadata):
    patched = []
    for path in sorted(zarr_root.rglob("*.ome.xml")):
        if patch_ome_xml_file(path, metadata):
            patched.append(str(path))
    return patched


def main():
    parser = argparse.ArgumentParser(
        description="Patch extracted PLASTIC/LIF metadata into an OME-Zarr .zattrs file."
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

    attrs["plastic_metadata"] = compact_plastic_metadata(metadata)
    zattrs_path.write_text(json.dumps(attrs, indent=2, sort_keys=True), encoding="utf-8")
    patched_ome_xmls = patch_ome_xml_files(zarr_root, metadata)

    with Path(args.log).open("w", encoding="utf-8") as handle:
        handle.write("omezarr\tmetadata_json\tpatched_zattrs\tchannels\tpatched_ome_xmls\n")
        handle.write(
            f"{zarr_root}\t{args.metadata_json}\t{zattrs_path}\t"
            f"{len(omero_channels)}\t{len(patched_ome_xmls)}\n"
        )


if __name__ == "__main__":
    main()
