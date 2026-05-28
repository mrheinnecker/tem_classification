import argparse
import ast
import json
from pathlib import Path

import tifffile


UNIT_TO_NM = {
    "nm": 1.0,
    "um": 1000.0,
    "micrometer": 1000.0,
    "micrometre": 1000.0,
    "\u00b5m": 1000.0,
    "\u75e0": 1000.0,
    "mm": 1_000_000.0,
    "m": 1_000_000_000.0,
    "fm": 1e-6,
}


def json_safe(value):
    if isinstance(value, (str, int, float, bool)) or value is None:
        return value
    if isinstance(value, dict):
        return {str(k): json_safe(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_safe(v) for v in value]
    return str(value)


def parse_cz_sem(cz_sem_value):
    if cz_sem_value is None:
        return {}
    if isinstance(cz_sem_value, dict):
        return cz_sem_value
    if isinstance(cz_sem_value, bytes):
        cz_sem_value = cz_sem_value.decode("utf-8", errors="replace")
    if isinstance(cz_sem_value, str):
        try:
            parsed = ast.literal_eval(cz_sem_value)
        except (SyntaxError, ValueError):
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def cz_entry(cz_sem, key):
    value = cz_sem.get(key)
    if isinstance(value, (list, tuple)) and len(value) >= 2:
        label = value[0]
        numeric_value = value[1]
        unit = value[2] if len(value) >= 3 else None
        return {
            "key": key,
            "label": label,
            "value": numeric_value,
            "unit": unit,
        }
    return None


def value_in_nm(entry):
    if not entry:
        return None
    try:
        value = float(entry["value"])
    except (TypeError, ValueError):
        return None
    unit = str(entry.get("unit") or "nm").strip()
    factor = UNIT_TO_NM.get(unit)
    if factor is None:
        return None
    return value * factor


def int_tag(tags, key):
    try:
        return int(tags[key])
    except (KeyError, TypeError, ValueError):
        return None


def derive_pixel_size_from_field_of_view(cz_sem, width_px, height_px):
    width = cz_entry(cz_sem, "ap_width")
    height = cz_entry(cz_sem, "ap_height")
    width_nm = value_in_nm(width)
    height_nm = value_in_nm(height)

    derived = {}
    if width_nm is not None and width_px:
        derived["x_nm"] = width_nm / width_px
        derived["x_source"] = width
    if height_nm is not None and height_px:
        derived["y_nm"] = height_nm / height_px
        derived["y_source"] = height

    if derived.get("x_nm") is not None and derived.get("y_nm") is not None:
        derived["mean_nm"] = (derived["x_nm"] + derived["y_nm"]) / 2

    return derived


def extract_sem_metadata(tif_path):
    metadata = {
        "input_file": str(tif_path),
        "image": {},
        "pixel_size": {},
        "sem": {},
        "candidates": {},
    }

    with tifffile.TiffFile(tif_path) as tif:
        page = tif.pages[0]
        tags = {}
        for tag in page.tags.values():
            try:
                tags[tag.name] = json_safe(tag.value)
            except Exception:
                tags[tag.name] = "UNREADABLE"

        cz_sem = parse_cz_sem(tags.get("CZ_SEM"))
        width_px = int_tag(tags, "ImageWidth")
        height_px = int_tag(tags, "ImageLength")

        metadata["image"] = {
            "width_px": width_px,
            "height_px": height_px,
            "dtype": str(tif.series[0].dtype) if tif.series else None,
            "axes": str(tif.series[0].axes) if tif.series else None,
            "shape": list(tif.series[0].shape) if tif.series else None,
        }

        candidate_keys = [
            "ap_image_pixel_size",
            "ap_pixel_size",
            "ap_fib_pixel_size",
            "ap_ar_pixel_size",
        ]
        candidates = {}
        for key in candidate_keys:
            entry = cz_entry(cz_sem, key)
            if entry:
                entry["value_nm"] = value_in_nm(entry)
                candidates[key] = entry

        fov_derived = derive_pixel_size_from_field_of_view(cz_sem, width_px, height_px)
        if fov_derived:
            candidates["field_of_view_derived"] = fov_derived

        chosen = candidates.get("ap_image_pixel_size")
        source = "ap_image_pixel_size"
        if not chosen or chosen.get("value_nm") is None:
            chosen = candidates.get("field_of_view_derived")
            source = "field_of_view_derived"
        if chosen and source == "field_of_view_derived":
            pixel_size_x = chosen.get("x_nm")
            pixel_size_y = chosen.get("y_nm")
        elif chosen:
            pixel_size_x = chosen.get("value_nm")
            pixel_size_y = chosen.get("value_nm")
        else:
            pixel_size_x = None
            pixel_size_y = None
            source = None

        metadata["pixel_size"] = {
            "x_nm": pixel_size_x,
            "y_nm": pixel_size_y,
            "unit": "nm",
            "source": source,
        }
        metadata["sem"] = {
            "instrument": cz_entry(cz_sem, "dp_sem"),
            "column": cz_entry(cz_sem, "dp_column_type"),
            "detector": cz_entry(cz_sem, "dp_detector_type"),
            "magnification": cz_entry(cz_sem, "ap_mag"),
            "date": cz_entry(cz_sem, "ap_date"),
            "time": cz_entry(cz_sem, "ap_time"),
        }
        metadata["candidates"] = candidates

    return metadata


def main():
    parser = argparse.ArgumentParser(
        description="Extract workflow-ready metadata from Zeiss SEM TIFF files."
    )
    parser.add_argument("input", help="Input SEM TIFF file")
    parser.add_argument(
        "output",
        nargs="?",
        help="Output JSON file. Defaults to <input>_metadata.json",
    )
    args = parser.parse_args()

    tif_path = Path(args.input)
    output_path = Path(args.output) if args.output else tif_path.with_name(
        f"{tif_path.stem}_metadata.json"
    )

    metadata = extract_sem_metadata(tif_path)
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)
        f.write("\n")

    pixel_size = metadata["pixel_size"]
    print(f"Saved metadata to: {output_path}")
    print(
        "Pixel size: "
        f"x={pixel_size['x_nm']} nm, y={pixel_size['y_nm']} nm "
        f"(source: {pixel_size['source']})"
    )


if __name__ == "__main__":
    main()
