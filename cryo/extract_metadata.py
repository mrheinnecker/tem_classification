import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import tifffile
except ImportError:
    tifffile = None

try:
    from aicspylibczi import CziFile
except ImportError:
    CziFile = None


UNIT_TO_NM = {
    "nm": 1.0,
    "nanometer": 1.0,
    "nanometers": 1.0,
    "nanometre": 1.0,
    "nanometres": 1.0,
    "um": 1000.0,
    "micron": 1000.0,
    "microns": 1000.0,
    "micrometer": 1000.0,
    "micrometers": 1000.0,
    "micrometre": 1000.0,
    "micrometres": 1000.0,
    "mm": 1_000_000.0,
    "millimeter": 1_000_000.0,
    "millimeters": 1_000_000.0,
    "millimetre": 1_000_000.0,
    "millimetres": 1_000_000.0,
}
METER_TO_NM = 1_000_000_000.0


def parse_optional_float(value):
    value = "" if value is None else str(value).strip()
    if value == "":
        return None
    return float(value)


def to_nm(value, unit):
    if value is None:
        return None
    normalized = (unit or "nm").strip().lower()
    if normalized not in UNIT_TO_NM:
        raise ValueError(f"Unsupported scale unit: {unit}")
    return float(value) * UNIT_TO_NM[normalized]


def tag_value(page, name):
    tag = page.tags.get(name)
    return tag.value if tag is not None else None


def rational_to_float(value):
    if isinstance(value, tuple) and len(value) == 2:
        numerator, denominator = value
        return float(numerator) / float(denominator)
    return float(value)


def resolution_pixel_size_nm(page):
    x_resolution = tag_value(page, "XResolution")
    y_resolution = tag_value(page, "YResolution")
    resolution_unit = tag_value(page, "ResolutionUnit")
    if x_resolution is None or y_resolution is None or resolution_unit is None:
        return None, None

    unit_to_nm = {
        2: 25_400_000.0,
        3: 10_000_000.0,
    }
    if int(resolution_unit) not in unit_to_nm:
        return None, None

    x_per_unit = rational_to_float(x_resolution)
    y_per_unit = rational_to_float(y_resolution)
    if x_per_unit <= 0 or y_per_unit <= 0:
        return None, None
    unit_nm = unit_to_nm[int(resolution_unit)]
    return unit_nm / x_per_unit, unit_nm / y_per_unit


def parse_imagej_description(description):
    metadata = {}
    for line in str(description or "").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        metadata[key.strip().lower()] = value.strip()

    unit = metadata.get("unit", "um")
    spacing = parse_optional_float(metadata.get("spacing"))
    z_nm = to_nm(spacing, unit) if spacing is not None else None
    return z_nm


def ome_namespace(root):
    match = re.match(r"\{(.+)\}", root.tag)
    return {"ome": match.group(1)} if match else {}


def parse_ome_xml(description):
    if not description or "PhysicalSize" not in description:
        return {}
    try:
        root = ET.fromstring(description)
    except ET.ParseError:
        return {}

    ns = ome_namespace(root)
    pixels = root.find(".//ome:Pixels", ns) if ns else root.find(".//Pixels")
    if pixels is None:
        return {}

    values = {}
    for axis in ("X", "Y", "Z"):
        size = parse_optional_float(pixels.attrib.get(f"PhysicalSize{axis}"))
        unit = pixels.attrib.get(f"PhysicalSize{axis}Unit", "um")
        values[f"{axis.lower()}_scale_nm"] = to_nm(size, unit) if size is not None else None
    values["dimension_order"] = pixels.attrib.get("DimensionOrder")
    for axis in ("X", "Y", "Z", "C", "T"):
        raw_value = pixels.attrib.get(f"Size{axis}")
        values[f"size_{axis.lower()}"] = int(raw_value) if raw_value is not None else None
    return values


def first_text(element, names):
    for name in names:
        child = element.find(f".//{name}")
        if child is not None and child.text:
            return child.text
    return None


def czi_scaling_from_xml(xml_text):
    root = ET.fromstring(xml_text)
    values = {}

    for distance in root.findall(".//Distance"):
        axis = distance.attrib.get("Id", "").strip().upper()
        if axis not in {"X", "Y", "Z"}:
            continue
        value_text = first_text(distance, ["Value", "DefaultValue"])
        if value_text is None:
            continue
        values[f"{axis.lower()}_scale_nm"] = float(value_text) * METER_TO_NM

    return values


def extract_czi_metadata(path):
    if CziFile is None:
        raise RuntimeError("aicspylibczi is required to read CZI metadata")

    czi = CziFile(path)
    metadata = {}
    xml_text = czi.meta
    if isinstance(xml_text, bytes):
        xml_text = xml_text.decode("utf-8", errors="replace")
    if xml_text:
        metadata.update(czi_scaling_from_xml(xml_text))
    try:
        metadata["dims_shape"] = czi.dims_shape()
    except Exception:
        metadata["dims_shape"] = None
    return metadata


def extract_tiff_metadata(path):
    if tifffile is None:
        raise RuntimeError("tifffile is required to read TIFF metadata")

    metadata = {}
    with tifffile.TiffFile(path) as tif:
        series = tif.series[0] if tif.series else None
        page = tif.pages[0]
        description = tag_value(page, "ImageDescription") or ""

        metadata.update(parse_ome_xml(description))
        x_from_resolution, y_from_resolution = resolution_pixel_size_nm(page)
        if metadata.get("x_scale_nm") is None:
            metadata["x_scale_nm"] = x_from_resolution
        if metadata.get("y_scale_nm") is None:
            metadata["y_scale_nm"] = y_from_resolution
        if metadata.get("z_scale_nm") is None:
            metadata["z_scale_nm"] = parse_imagej_description(description)
        metadata["shape"] = list(series.shape) if series is not None else list(page.shape)
        metadata["axes"] = getattr(series, "axes", None) if series is not None else None
        metadata["page_count"] = len(tif.pages)
        metadata["is_ome"] = bool(tif.is_ome)
        metadata["is_imagej"] = bool(tif.is_imagej)
    return metadata


def merge_overrides(metadata, args):
    overrides = {
        "x_scale_nm": to_nm(parse_optional_float(args.x_scale), args.scale_unit),
        "y_scale_nm": to_nm(parse_optional_float(args.y_scale), args.scale_unit),
        "z_scale_nm": to_nm(parse_optional_float(args.z_scale), args.scale_unit),
    }
    for key, value in overrides.items():
        if value is not None:
            metadata[key] = value
    return metadata


def main():
    parser = argparse.ArgumentParser(
        description="Extract CRYO/light-microscopy pixel and Z spacing metadata."
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--pixel-size-tsv", required=True)
    parser.add_argument("--x-scale", default="")
    parser.add_argument("--y-scale", default="")
    parser.add_argument("--z-scale", default="")
    parser.add_argument("--scale-unit", default="nm")
    args = parser.parse_args()

    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Raw image does not exist: {input_path}")

    metadata = {
        "name": args.name,
        "raw_path": str(input_path),
        "source_suffix": input_path.suffix.lower(),
    }

    suffixes = [suffix.lower() for suffix in input_path.suffixes]
    if input_path.suffix.lower() == ".czi":
        try:
            metadata.update(extract_czi_metadata(input_path))
        except RuntimeError:
            if not all([args.x_scale, args.y_scale, args.z_scale]):
                raise
    elif input_path.suffix.lower() in {".tif", ".tiff"} or suffixes[-2:] in [[".ome", ".tif"], [".ome", ".tiff"]]:
        try:
            metadata.update(extract_tiff_metadata(input_path))
        except RuntimeError:
            if not all([args.x_scale, args.y_scale, args.z_scale]):
                raise
    metadata = merge_overrides(metadata, args)

    missing = [
        key
        for key in ("x_scale_nm", "y_scale_nm", "z_scale_nm")
        if metadata.get(key) is None
    ]
    if missing:
        raise ValueError(
            "Missing required scale metadata "
            + ", ".join(missing)
            + ". Add OME/ImageJ metadata to the file or provide sheet columns/launcher defaults."
        )

    Path(args.metadata_json).write_text(
        json.dumps(metadata, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    with Path(args.pixel_size_tsv).open("w", encoding="utf-8") as handle:
        handle.write("x_nm\ty_nm\tz_nm\n")
        handle.write(
            f"{metadata['x_scale_nm']}\t{metadata['y_scale_nm']}\t{metadata['z_scale_nm']}\n"
        )


if __name__ == "__main__":
    main()
