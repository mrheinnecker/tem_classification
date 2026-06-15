import argparse
import json
import re
from pathlib import Path


def json_safe(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (list, tuple)):
        return [json_safe(item) for item in value]
    if isinstance(value, dict):
        return {str(key): json_safe(item) for key, item in value.items()}
    return str(value)


def simple_attrs(obj, names=None):
    values = {}
    iterable = names if names is not None else dir(obj)
    for name in iterable:
        if name.startswith("_"):
            continue
        try:
            value = getattr(obj, name)
        except Exception:
            continue
        if callable(value):
            continue
        if isinstance(value, (str, int, float, bool, type(None), list, tuple, dict)):
            values[name] = json_safe(value)
        elif name.lower() in {"dims", "shape", "physical_pixel_sizes", "channel_names"}:
            values[name] = str(value)
    return values


def text_preview(path, limit):
    raw = path.read_bytes()
    encodings = ["utf-8", "utf-16", "latin-1"]
    for encoding in encodings:
        try:
            text = raw.decode(encoding)
            printable = sum(1 for char in text[:1000] if char.isprintable() or char.isspace())
            if printable / max(1, min(len(text), 1000)) > 0.8:
                return {
                    "encoding": encoding,
                    "size_bytes": len(raw),
                    "preview": text[:limit],
                }
        except UnicodeDecodeError:
            continue
    return {
        "encoding": None,
        "size_bytes": len(raw),
        "preview": raw[: min(limit, 256)].hex(),
    }


def decode_text(path):
    raw = path.read_bytes()
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


def channel_descriptions(text):
    descriptions = []
    for match in re.finditer(r"<ChannelDescription\b([^>]*)>", text, flags=re.IGNORECASE):
        descriptions.append(parse_xml_attributes(match.group(1)))
    return descriptions


def lifext_candidates(path):
    return [
        path.with_suffix(".lifext"),
        Path(str(path) + "ext"),
        path.parent / f"{path.name}.lifext",
    ]


def inspect_lifext(path, limit):
    seen = set()
    results = []
    for candidate in lifext_candidates(path):
        if candidate in seen:
            continue
        seen.add(candidate)
        if not candidate.exists():
            continue
        info = text_preview(candidate, limit)
        text = decode_text(candidate)
        info["path"] = str(candidate)
        descriptions = channel_descriptions(text)
        if descriptions:
            info["channel_descriptions"] = descriptions
        channels = sorted(
            set(
                re.findall(
                    r"(?:Channel|Detector|Dye|LUT|Fluo|Wavelength)[^<\n\r]{0,120}",
                    text[: max(limit, 100000)],
                    flags=re.IGNORECASE,
                )
            )
        )
        if channels:
            info["metadata_like_terms"] = channels[:50]
        results.append(info)
    return results


def inspect_bioimage(path):
    from bioio import BioImage

    image = BioImage(path)
    result = {
        "object": simple_attrs(
            image,
            names=[
                "current_scene",
                "dims",
                "shape",
                "physical_pixel_sizes",
                "channel_names",
                "scenes",
            ],
        ),
        "scenes": [str(scene) for scene in (getattr(image, "scenes", []) or [])],
        "per_scene": [],
    }
    scenes = getattr(image, "scenes", []) or [None]
    for scene in scenes:
        scene_info = {"scene": str(scene) if scene is not None else None}
        try:
            if scene is not None:
                image.set_scene(scene)
        except Exception as exc:
            scene_info["set_scene_error"] = repr(exc)
            result["per_scene"].append(scene_info)
            continue

        for attr in ("dims", "shape", "physical_pixel_sizes", "channel_names"):
            try:
                scene_info[attr] = json_safe(getattr(image, attr))
            except Exception as exc:
                scene_info[f"{attr}_error"] = repr(exc)

        try:
            data = image.xarray_dask_data
            scene_info["xarray_dims"] = list(data.dims)
            scene_info["xarray_shape"] = list(data.shape)
            scene_info["xarray_coords"] = {
                str(name): [str(item) for item in coord.values.tolist()]
                for name, coord in data.coords.items()
                if coord.ndim == 1 and coord.size <= 100
            }
        except Exception as exc:
            scene_info["xarray_error"] = repr(exc)

        result["per_scene"].append(scene_info)
    return result


def inspect_readlif(path, max_images):
    try:
        from readlif.reader import LifFile
    except ImportError as exc:
        return {"error": f"readlif import failed: {exc}"}

    try:
        lif = LifFile(str(path))
    except Exception as exc:
        return {"error": f"LifFile open failed: {exc!r}"}

    result = {
        "object": simple_attrs(
            lif,
            names=[
                "filename",
                "xml_header",
                "xml_root",
            ],
        ),
        "images": [],
    }
    try:
        iterator = lif.get_iter_image()
    except Exception as exc:
        result["iter_error"] = repr(exc)
        return result

    for index, image in enumerate(iterator):
        if index >= max_images:
            result["truncated_after"] = max_images
            break
        info = {
            "index": index,
            "object": simple_attrs(
                image,
                names=[
                    "name",
                    "dims",
                    "scale",
                    "channels",
                    "settings",
                    "info",
                    "path",
                ],
            ),
        }
        for name in ("name", "dims", "scale", "channels", "settings", "info"):
            try:
                value = getattr(image, name)
                info[name] = json_safe(value)
            except Exception:
                pass
        result["images"].append(info)
    return result


def main():
    parser = argparse.ArgumentParser(
        description="Inspect Leica LIF/LIFEXT metadata without converting image data."
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--output-json", default="")
    parser.add_argument("--max-images", type=int, default=20)
    parser.add_argument("--preview-chars", type=int, default=5000)
    args = parser.parse_args()

    path = Path(args.input)
    if not path.exists():
        raise FileNotFoundError(path)

    report = {
        "input": str(path),
        "lifext": inspect_lifext(path, args.preview_chars),
        "bioimage": None,
        "readlif": None,
    }
    try:
        report["bioimage"] = inspect_bioimage(path)
    except Exception as exc:
        report["bioimage"] = {"error": repr(exc)}

    report["readlif"] = inspect_readlif(path, args.max_images)

    text = json.dumps(report, indent=2, sort_keys=True)
    if args.output_json:
        Path(args.output_json).write_text(text, encoding="utf-8")
    else:
        print(text)


if __name__ == "__main__":
    main()
