import argparse
import json
import os
import shutil
from pathlib import Path


def load_bioimage(path):
    try:
        from bioio import BioImage
        import numpy as np
    except ImportError as exc:
        raise RuntimeError(
            "bioio and numpy are required to convert CZI inputs to OME-TIFF"
        ) from exc

    image = BioImage(path)
    data = image.get_image_data("TCZYX")
    return np.asarray(data)


def write_czi_as_ome_tiff(input_path, output_path):
    try:
        import tifffile
    except ImportError as exc:
        raise RuntimeError("tifffile is required to write intermediate OME-TIFF") from exc

    data = load_bioimage(input_path)
    tifffile.imwrite(
        output_path,
        data,
        bigtiff=True,
        ome=True,
        photometric="minisblack",
        metadata={"axes": "TCZYX"},
    )


def link_or_copy(source, target):
    try:
        os.symlink(source, target)
    except OSError:
        shutil.copy2(source, target)


def main():
    parser = argparse.ArgumentParser(
        description="Prepare CRYO raw inputs for EuBI-Bridge conversion."
    )
    parser.add_argument("--input", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--metadata-json", required=True)
    parser.add_argument("--prepared-log", required=True)
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    if not input_path.exists():
        raise FileNotFoundError(f"Raw image does not exist: {input_path}")

    output_dir.mkdir(parents=True, exist_ok=True)
    suffix = input_path.suffix.lower()

    if suffix == ".czi":
        prepared_path = output_dir / f"{args.name}.ome.tif"
        write_czi_as_ome_tiff(input_path, prepared_path)
        mode = "czi_to_ome_tiff"
    else:
        prepared_path = output_dir / input_path.name
        link_or_copy(input_path, prepared_path)
        mode = "link_or_copy_original"

    metadata = {}
    metadata_path = Path(args.metadata_json)
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    metadata["prepared_input_path"] = str(prepared_path)
    metadata["prepared_input_mode"] = mode
    metadata_path.write_text(
        json.dumps(metadata, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    with Path(args.prepared_log).open("w", encoding="utf-8") as handle:
        handle.write("name\traw_path\tprepared_path\tmode\n")
        handle.write(f"{args.name}\t{input_path}\t{prepared_path}\t{mode}\n")


if __name__ == "__main__":
    main()
