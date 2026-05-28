

## SEM: /g/schwab/Chandni/SEM/IMATREC SEM

## in the collection tabel: site date, time, TARA-overalp fraction, annotation


## cryo samples










 eubi to_zarr \
    /g/schwab/marco/tiftest/ATH_20240701_PM_104.tif \
    /g/schwab/marco/tiftest/out_omezarr \
      --x_unit nm \
      --y_unit nm \
      --x_scale "${params.pixel_scale_x}" \
      --y_scale "${params.pixel_scale_y}"
