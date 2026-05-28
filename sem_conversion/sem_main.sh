

## SEM: /g/schwab/Chandni/SEM/IMATREC SEM

## in the collection tabel: site date, time, TARA-overalp fraction, annotation


## cryo samples



singularity shell --bind /g --bind /scratch /g/schwab/marco/container_legacy/python_latest.sif

cd /g/schwab/marco/repos/tem_classification

python sem_conversion/extract_metadata.py /g/schwab/marco/tiftest/ATH_20240701_PM_104.tif /g/schwab/marco/tiftest/output_metadata.json





 eubi to_zarr \
    /g/schwab/marco/tiftest/ATH_20240701_PM_104.tif \
    /g/schwab/marco/tiftest/out_omezarr \
      --x_unit nm \
      --y_unit nm \
      --x_scale "${params.pixel_scale_x}" \
      --y_scale "${params.pixel_scale_y}"
