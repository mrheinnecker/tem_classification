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
    from bioio import BioImage
except ImportError:
    BioImage = None

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
DEFAULT_CHANNEL_COLORS = [
    "red",
    "green",
    "yellow",
    "blue",
    "magenta",
    "cyan",
    "white",
]
CHANNEL_COLOR_OVERRIDES = {
    "gfp": "cyan",
    "tl": "white",
    "chloa": "magenta",
    "chlorophyll": "magenta",
    "pe": "yellow",
}


def parse_optional_float(value):
    value = "" if value is None else str(value).strip()
    if value == "" or value.lower() in {"true", "false", "na", "nan", "none", "null"}:
        return None
    return float(value)


def parse_first_number(value):
    value = "" if value is None else str(value).strip()
    if value == "":
        return None
    match = re.search(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?", value)
    if not match:
        return None
    return float(match.group(0))


def parse_wavelength_nm(value, unit="nm"):
    parsed = parse_first_number(value)
    if parsed is None:
        return None
    return to_nm(parsed, unit)


def to_nm(value, unit):
    if value is None:
        return None
    normalized = (
        (unit or "nm")
        .strip()
        .lower()
        .replace("\u00b5", "u")
        .replace("\u03bc", "u")
    )
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
    channels = []
    channel_elements = pixels.findall("ome:Channel", ns) if ns else pixels.findall("Channel")
    for index, channel in enumerate(channel_elements):
        label = (
            channel.attrib.get("Name")
            or channel.attrib.get("ID")
            or f"channel_{index}"
        )
        channels.append(
            {
                "index": index,
                "label": label,
                "display": sanitize_channel_label(label, index),
                "color": color_for_channel(label, None, index),
                "fluor": channel.attrib.get("Fluor"),
                "excitation_wavelength_nm": parse_wavelength_nm(
                    channel.attrib.get("ExcitationWavelength"),
                    channel.attrib.get("ExcitationWavelengthUnit", "nm"),
                ),
                "emission_wavelength_nm": parse_wavelength_nm(
                    channel.attrib.get("EmissionWavelength"),
                    channel.attrib.get("EmissionWavelengthUnit", "nm"),
                ),
            }
        )
    if channels:
        values["channels"] = channels
    return values


def local_name(element):
    return str(element.tag).split("}", 1)[-1]


def find_children_by_local_name(element, name):
    return [child for child in list(element) if local_name(child) == name]


def find_first_text_by_local_name(element, names):
    wanted = set(names)
    for child in element.iter():
        if local_name(child) in wanted and child.text and child.text.strip():
            return child.text.strip()
    return None


def find_first_wavelength_nm(element, names):
    for name in names:
        for child in element.iter():
            if local_name(child) != name:
                continue
            raw_value = child.attrib.get("Value") or child.text
            unit = (
                child.attrib.get("Unit")
                or child.attrib.get(f"{name}Unit")
                or child.attrib.get("DefaultUnit")
                or "nm"
            )
            parsed = parse_wavelength_nm(raw_value, unit)
            if parsed is not None:
                return parsed
    return None


def first_text(element, names):
    for name in names:
        child = element.find(f".//{name}")
        if child is not None and child.text:
            return child.text
    return None


def sanitize_channel_label(label, index):
    label = str(label or "").strip()
    if not label:
        return f"channel_{index}"
    cleaned = re.sub(r"[^A-Za-z0-9]+", "_", label).strip("_")
    return cleaned or f"channel_{index}"


def color_for_channel(label, raw_color, index):
    label_lower = str(label or "").lower()
    compact_label = re.sub(r"[^a-z0-9]+", "", label_lower)
    if compact_label == "green":
        return "cyan"
    if compact_label in {"gray", "grey"}:
        return "white"
    if compact_label == "yellow":
        return "yellow"
    if compact_label in {"magenta", "red"}:
        return "magenta"
    for key, color in CHANNEL_COLOR_OVERRIDES.items():
        if key in compact_label:
            return color
    if "dapi" in label_lower or "hoechst" in label_lower:
        return "blue"
    if "gfp" in label_lower or "fitc" in label_lower or "488" in label_lower:
        return "cyan"
    if "rfp" in label_lower or "tritc" in label_lower or "mcherry" in label_lower or "561" in label_lower:
        return "magenta"
    if "cy5" in label_lower or "647" in label_lower or "farred" in label_lower:
        return "magenta"
    return DEFAULT_CHANNEL_COLORS[index % len(DEFAULT_CHANNEL_COLORS)]


def canonical_channel_display(label, fluor=None, excitation_wavelength=None, emission_wavelength=None):
    text = " ".join(str(value or "") for value in (label, fluor)).lower()
    compact = re.sub(r"[^a-z0-9]+", "", text)
    if compact == "magenta":
        return "Red"
    if "tl" in compact and "tpmt" not in compact:
        return "TL"
    if any(term in compact for term in ("gfp", "egfp", "fitc")):
        return "GFP"
    if any(term in compact for term in ("pe", "af555", "alexafluor555")):
        return "PE"
    if any(term in compact for term in ("chloa", "chlorophylla")):
        return "ChloA"

    excitation = round(float(excitation_wavelength)) if excitation_wavelength is not None else None
    emission = round(float(emission_wavelength)) if emission_wavelength is not None else None
    if excitation == 488 or emission == 509:
        return "GFP"
    if excitation == 553 or emission == 568:
        return "PE"
    if excitation == 655 or emission == 667:
        return "ChloA"
    return None


def zeiss_color_to_mobie(value):
    value = str(value or "").strip()
    if not value:
        return None
    match = re.fullmatch(r"#?([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})", value)
    if not match:
        return None
    hex_color = match.group(1)
    if len(hex_color) == 8:
        alpha = int(hex_color[0:2], 16)
        red = int(hex_color[2:4], 16)
        green = int(hex_color[4:6], 16)
        blue = int(hex_color[6:8], 16)
    else:
        alpha = 255
        red = int(hex_color[0:2], 16)
        green = int(hex_color[2:4], 16)
        blue = int(hex_color[4:6], 16)
    return f"r({red})-g({green})-b({blue})-a({alpha})"


def czi_channel_count_from_dims_shape(dims_shape):
    if isinstance(dims_shape, dict):
        value = dims_shape.get("C")
        if isinstance(value, (list, tuple)) and len(value) == 2:
            return int(value[1] - value[0])
        if isinstance(value, int):
            return int(value)
    if isinstance(dims_shape, list):
        for item in dims_shape:
            count = czi_channel_count_from_dims_shape(item)
            if count is not None:
                return count
    return None


def normalized_channel_key(value):
    value = "" if value is None else str(value).strip()
    if value == "":
        return None
    match = re.search(r"channel[:_\s-]*(\d+)", value, flags=re.IGNORECASE)
    if match:
        return f"channel_{int(match.group(1))}"
    return sanitize_channel_label(value, 0).lower()


def channel_element_keys(element):
    keys = []
    for attr_name in ("Name", "Id", "ID"):
        key = normalized_channel_key(element.attrib.get(attr_name))
        if key and key not in keys:
            keys.append(key)
    return keys


def matching_channel_text(channel_elements, label, names):
    wanted_keys = set()
    for value in (label,):
        key = normalized_channel_key(value)
        if key:
            wanted_keys.add(key)
    for element in channel_elements:
        if not wanted_keys.intersection(channel_element_keys(element)):
            continue
        value = find_first_text_by_local_name(element, names)
        if value:
            return value
    return None


def czi_channels_from_xml(xml_text, max_channels=None):
    if isinstance(xml_text, ET.Element):
        root = xml_text
    else:
        if isinstance(xml_text, bytes):
            xml_text = xml_text.decode("utf-8", errors="replace")
        root = ET.fromstring(xml_text)

    channels_parents = [
        element
        for element in root.iter()
        if local_name(element) == "Channels"
    ]
    channel_elements = []
    for parent in channels_parents:
        direct_channels = find_children_by_local_name(parent, "Channel")
        if direct_channels:
            channel_elements.extend(direct_channels)
    if not channel_elements:
        channel_elements = [
            element
            for element in root.iter()
            if local_name(element) == "Channel"
        ]
    channels = []
    seen = set()
    for element in channel_elements:
        label = (
            element.attrib.get("Name")
            or find_first_text_by_local_name(element, ["Name", "DyeName", "Fluor", "Fluorophore"])
            or element.attrib.get("Id")
            or element.attrib.get("ID")
        )
        dye = find_first_text_by_local_name(element, ["DyeName", "Fluor", "Fluorophore"])
        if not dye:
            dye = matching_channel_text(
                channel_elements,
                label or element.attrib.get("Id") or element.attrib.get("ID"),
                ["DyeName", "Fluor", "Fluorophore"],
            )
        if dye and (not label or re.fullmatch(r"ch(?:annel)?_?\d+", str(label), flags=re.IGNORECASE)):
            label = dye
        raw_color = (
            element.attrib.get("Color")
            or find_first_text_by_local_name(element, ["Color", "ColorRGBA"])
        )
        excitation_wavelength = (
            parse_wavelength_nm(
                element.attrib.get("ExcitationWavelength"),
                element.attrib.get("ExcitationWavelengthUnit", "nm"),
            )
            or find_first_wavelength_nm(
                element,
                [
                    "ExcitationWavelength",
                    "ExcitationWavelengthMicron",
                    "ExcitationWavelengthUm",
                    "DyeMaxExcitation",
                ],
            )
        )
        emission_wavelength = (
            parse_wavelength_nm(
                element.attrib.get("EmissionWavelength"),
                element.attrib.get("EmissionWavelengthUnit", "nm"),
            )
            or find_first_wavelength_nm(
                element,
                [
                    "EmissionWavelength",
                    "EmissionWavelengthMicron",
                    "EmissionWavelengthUm",
                    "DyeMaxEmission",
                ],
            )
        )
        key = sanitize_channel_label(label, len(channels)).lower()
        if key in seen:
            continue
        seen.add(key)
        index = len(channels)
        label = label or f"channel_{index}"
        display = canonical_channel_display(
            label,
            dye,
            excitation_wavelength,
            emission_wavelength,
        ) or sanitize_channel_label(label, index)
        channels.append(
            {
                "index": index,
                "label": str(label),
                "display": display,
                "color": color_for_channel(display, raw_color, index),
                "fluor": str(dye) if dye else None,
                "excitation_wavelength_nm": excitation_wavelength,
                "emission_wavelength_nm": emission_wavelength,
            }
        )
        if max_channels is not None and len(channels) >= max_channels:
            break
    return channels


def czi_scaling_from_xml(xml_text):
    if isinstance(xml_text, ET.Element):
        root = xml_text
    else:
        if isinstance(xml_text, bytes):
            xml_text = xml_text.decode("utf-8", errors="replace")
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


def int_or_none(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def czi_dimension_summary_from_xml(xml_text):
    if isinstance(xml_text, ET.Element):
        root = xml_text
    else:
        if isinstance(xml_text, bytes):
            xml_text = xml_text.decode("utf-8", errors="replace")
        root = ET.fromstring(xml_text)

    values = {}
    for axis in ("X", "Y", "Z", "C", "T", "S", "M"):
        for element in root.iter():
            if local_name(element) == f"Size{axis}" and element.text:
                parsed = int_or_none(element.text)
                if parsed is not None:
                    values[f"size_{axis.lower()}"] = parsed
                break

    scenes = []
    for parent in root.iter():
        if local_name(parent) != "Scenes":
            continue
        for scene in find_children_by_local_name(parent, "Scene"):
            scenes.append(
                {
                    "index": int_or_none(scene.attrib.get("Index")),
                    "name": scene.attrib.get("Name"),
                    "region_id": first_text(scene, ["RegionId"]),
                    "scan_mode": first_text(scene, ["ScanMode"]),
                }
            )
        if scenes:
            break
    if scenes:
        values["scenes"] = scenes
        values["scene_count"] = len(scenes)
    return values


def extract_czi_metadata(path):
    if CziFile is None:
        raise RuntimeError("aicspylibczi is required to read CZI metadata")

    czi = CziFile(path)
    metadata = {}
    xml_text = czi.meta
    dims_shape = None
    try:
        dims_shape = czi.dims_shape()
        metadata["dims_shape"] = dims_shape
    except Exception:
        metadata["dims_shape"] = None
    channel_count = czi_channel_count_from_dims_shape(dims_shape)
    if channel_count is not None:
        metadata["size_c"] = channel_count
    if xml_text is not None:
        metadata.update(czi_dimension_summary_from_xml(xml_text))
        metadata.update(czi_scaling_from_xml(xml_text))
        channels = czi_channels_from_xml(xml_text, max_channels=channel_count)
        if channels:
            metadata["channels"] = channels
    return metadata


def czi_metadata_xml_text(path):
    if CziFile is None:
        raise RuntimeError("aicspylibczi is required to read CZI metadata")

    xml_text = CziFile(path).meta
    if xml_text is None:
        return ""
    if isinstance(xml_text, ET.Element):
        return ET.tostring(xml_text, encoding="unicode")
    if isinstance(xml_text, bytes):
        return xml_text.decode("utf-8", errors="replace")
    return str(xml_text)


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


def bioio_scale_to_nm(value):
    if value is None:
        return None
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    if value <= 0:
        return None
    return value * 1000.0


def bioio_physical_size(physical_pixel_sizes, axis):
    if physical_pixel_sizes is None:
        return None
    if hasattr(physical_pixel_sizes, axis):
        return getattr(physical_pixel_sizes, axis)
    if isinstance(physical_pixel_sizes, dict):
        return physical_pixel_sizes.get(axis) or physical_pixel_sizes.get(axis.lower())
    if isinstance(physical_pixel_sizes, (list, tuple)):
        index = {"Z": 0, "Y": 1, "X": 2}.get(axis)
        if index is not None and len(physical_pixel_sizes) > index:
            return physical_pixel_sizes[index]
    return None


def lifext_candidates(path):
    path = Path(path)
    return [
        path.with_suffix(".lifext"),
        Path(str(path) + "ext"),
        path.parent / f"{path.name}.lifext",
    ]


def decode_text_file(path):
    raw = Path(path).read_bytes()
    for encoding in ("utf-8", "utf-16", "latin-1"):
        try:
            text = raw.decode(encoding)
            printable = sum(1 for char in text[:1000] if char.isprintable() or char.isspace())
            if printable / max(1, min(len(text), 1000)) > 0.8:
                return text
        except UnicodeDecodeError:
            continue
    return ""


def parse_xml_attributes(text):
    return {
        key: value
        for key, value in re.findall(r'([A-Za-z_:][A-Za-z0-9_.:-]*)="([^"]*)"', text)
    }


def local_name(element):
    return element.tag.rsplit("}", 1)[-1] if "}" in element.tag else element.tag


def find_descendants_by_local_name(element, name):
    return [child for child in element.iter() if local_name(child) == name]


def child_text_by_local_name(element, name):
    for child in element:
        if local_name(child) == name:
            return child.text
    return None


def parse_optional_number(value):
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def channel_properties(element):
    properties = {}
    for prop in find_descendants_by_local_name(element, "ChannelProperty"):
        key = child_text_by_local_name(prop, "Key")
        value = child_text_by_local_name(prop, "Value")
        if key:
            properties[key] = value
    return properties


def beam_route_from_element(element):
    beam_route = next(
        (child for child in find_descendants_by_local_name(element, "BeamRoute")),
        None,
    )
    if beam_route is None:
        return None
    positions = []
    for position in find_descendants_by_local_name(beam_route, "BeamPosition"):
        level = parse_optional_number(position.attrib.get("BeamPositionLevel"))
        value = position.attrib.get("BeamPosition")
        if level is not None and value is not None:
            positions.append((int(level), value))
    if not positions:
        return None
    return ";".join(value for _, value in sorted(positions))


def parse_lifext_xml(path):
    text = decode_text_file(path)
    if not text:
        return None
    try:
        return ET.fromstring(text)
    except ET.ParseError:
        return None


def lifext_sidecar_metadata(path):
    for candidate in lifext_candidates(path):
        if not candidate.exists():
            continue
        root = parse_lifext_xml(candidate)
        if root is not None:
            descriptions = []
            for element in find_descendants_by_local_name(root, "ChannelDescription"):
                properties = channel_properties(element)
                row = dict(element.attrib)
                row["channel_properties"] = properties
                row["beam_route"] = properties.get("BeamRoute")
                row["detector"] = properties.get("DetectorName")
                row["dye_name"] = properties.get("DyeName")
                descriptions.append(row)

            spectral_bands = []
            bands_by_route = {}
            for element in find_descendants_by_local_name(root, "MultiBand"):
                route = beam_route_from_element(element)
                row = dict(element.attrib)
                row["beam_route"] = route
                row["emission_begin_nm"] = parse_optional_number(
                    row.get("TargetWaveLengthBegin") or row.get("LeftWorld")
                )
                row["emission_end_nm"] = parse_optional_number(
                    row.get("TargetWaveLengthEnd") or row.get("RightWorld")
                )
                spectral_bands.append(row)
                if route and route not in bands_by_route:
                    bands_by_route[route] = row

            detectors_by_channel = {}
            for element in find_descendants_by_local_name(root, "Detector"):
                channel = element.attrib.get("Channel")
                if not channel:
                    continue
                detector = dict(element.attrib)
                reference = next(
                    (
                        child
                        for child in find_descendants_by_local_name(element, "DetectionReferenceLine")
                    ),
                    None,
                )
                if reference is not None:
                    detector["laser_name"] = reference.attrib.get("LaserName")
                    detector["laser_wavelength_nm"] = parse_optional_number(
                        reference.attrib.get("LaserWavelength")
                    )
                detectors_by_channel[channel] = detector

            for row in descriptions:
                route = row.get("beam_route")
                band = bands_by_route.get(route)
                if band:
                    row["emission_begin_nm"] = band.get("emission_begin_nm")
                    row["emission_end_nm"] = band.get("emission_end_nm")
                    row["emission_wavelength_nm"] = midpoint(
                        band.get("emission_begin_nm"),
                        band.get("emission_end_nm"),
                    )
                    row["spectral_channel"] = band.get("Channel")
                detector = detectors_by_channel.get(str(row.get("spectral_channel")))
                if detector:
                    laser_wavelength = detector.get("laser_wavelength_nm")
                    if laser_wavelength and laser_wavelength > 0:
                        row["excitation_wavelength_nm"] = laser_wavelength
                    row["laser_name"] = detector.get("laser_name")

            return {
                "channel_descriptions": descriptions,
                "spectral_bands": spectral_bands,
            }

        text = decode_text_file(candidate)
        descriptions = []
        for match in re.finditer(r"<ChannelDescription\b([^>]*)>", text, flags=re.IGNORECASE):
            descriptions.append(parse_xml_attributes(match.group(1)))
        if descriptions:
            return {"channel_descriptions": descriptions, "spectral_bands": []}
    return {"channel_descriptions": [], "spectral_bands": []}


def midpoint(start, end):
    if start is None or end is None:
        return None
    return (float(start) + float(end)) / 2.0


def extract_lif_metadata(path):
    if BioImage is None:
        raise RuntimeError("bioio and bioio-lif are required to read LIF metadata")

    image = BioImage(path)
    metadata = {}

    scenes = list(getattr(image, "scenes", []) or [])
    if scenes:
        metadata["scenes"] = [
            {"index": index, "name": str(scene)}
            for index, scene in enumerate(scenes)
        ]
        metadata["scene_count"] = len(scenes)
        try:
            image.set_scene(scenes[0])
            metadata["selected_scene"] = str(scenes[0])
        except Exception:
            metadata["selected_scene"] = None

    physical_pixel_sizes = getattr(image, "physical_pixel_sizes", None)
    metadata["x_scale_nm"] = bioio_scale_to_nm(
        bioio_physical_size(physical_pixel_sizes, "X")
    )
    metadata["y_scale_nm"] = bioio_scale_to_nm(
        bioio_physical_size(physical_pixel_sizes, "Y")
    )
    metadata["z_scale_nm"] = bioio_scale_to_nm(
        bioio_physical_size(physical_pixel_sizes, "Z")
    )

    dims = getattr(image, "dims", None)
    metadata["axes"] = str(dims) if dims is not None else None
    shape = getattr(image, "shape", None)
    metadata["shape"] = list(shape) if shape is not None else None

    channel_names = list(getattr(image, "channel_names", []) or [])
    sidecar_metadata = lifext_sidecar_metadata(path)
    sidecar_channel_descriptions = sidecar_metadata.get("channel_descriptions", [])
    if sidecar_channel_descriptions:
        metadata["lifext_channel_descriptions"] = sidecar_channel_descriptions
    if sidecar_metadata.get("spectral_bands"):
        metadata["lifext_spectral_bands"] = sidecar_metadata["spectral_bands"]
    if not channel_names and sidecar_channel_descriptions:
        channel_names = [
            row.get("LUTName") or row.get("Name") or row.get("ChannelName")
            for row in sidecar_channel_descriptions
        ]
        channel_names = [name for name in channel_names if name]
    sidecar_by_lut = {
        str(row.get("LUTName") or "").lower(): row
        for row in sidecar_channel_descriptions
    }
    channels = []
    for index, label in enumerate(channel_names):
        sidecar_channel = sidecar_by_lut.get(str(label).lower(), {})
        display = canonical_channel_display(label) or sanitize_channel_label(label, index)
        channels.append(
            {
                "index": index,
                "label": str(label),
                "display": display,
                "color": color_for_channel(display, None, index),
                "fluor": sidecar_channel.get("dye_name") or None,
                "excitation_wavelength_nm": sidecar_channel.get("excitation_wavelength_nm"),
                "emission_wavelength_nm": sidecar_channel.get("emission_wavelength_nm"),
                "emission_begin_nm": sidecar_channel.get("emission_begin_nm"),
                "emission_end_nm": sidecar_channel.get("emission_end_nm"),
                "detector": sidecar_channel.get("detector"),
                "beam_route": sidecar_channel.get("beam_route"),
                "spectral_channel": sidecar_channel.get("spectral_channel"),
            }
        )
    if channels:
        metadata["channels"] = channels
        metadata["size_c"] = len(channels)

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
        description="Extract PLASTIC/light-microscopy pixel and Z spacing metadata."
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--pixel-size-tsv", required=True)
    parser.add_argument("--czi-metadata-xml", default="")
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
            if args.czi_metadata_xml:
                Path(args.czi_metadata_xml).write_text(
                    czi_metadata_xml_text(input_path),
                    encoding="utf-8",
                )
        except RuntimeError:
            if not all([args.x_scale, args.y_scale, args.z_scale]):
                raise
            if args.czi_metadata_xml:
                Path(args.czi_metadata_xml).write_text("", encoding="utf-8")
    elif input_path.suffix.lower() in {".tif", ".tiff"} or suffixes[-2:] in [[".ome", ".tif"], [".ome", ".tiff"]]:
        try:
            metadata.update(extract_tiff_metadata(input_path))
        except RuntimeError:
            if not all([args.x_scale, args.y_scale, args.z_scale]):
                raise
        if args.czi_metadata_xml:
            Path(args.czi_metadata_xml).write_text("", encoding="utf-8")
    elif input_path.suffix.lower() == ".lif":
        try:
            metadata.update(extract_lif_metadata(input_path))
        except RuntimeError:
            if not all([args.x_scale, args.y_scale, args.z_scale]):
                raise
        if args.czi_metadata_xml:
            Path(args.czi_metadata_xml).write_text("", encoding="utf-8")
    elif args.czi_metadata_xml:
        Path(args.czi_metadata_xml).write_text("", encoding="utf-8")
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
