#!bin/bash

workflow_dir="$1"

workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"

container_mrcfile="/g/schwab/marco/container_legacy/py_mrcfile.sif"
container_imod="/g/schwab/marco/container_legacy/EMBL_IMOD_5.1.0-foss-2023a-CUDA-12.1.1.sif"
container_tidyverse="/g/schwab/marco/container_devel/probeDesign_rtool.sif"

timestamp=$(date +%Y-%m-%d_%H-%M)

logdir="/g/schwab/tem_screen/logs/wfTEM_${timestamp}"
pngdir="/g/schwab/tem_screen/pngs"
outdir="/g/schwab/tem_screen/processed"
rawdir="/g/schwab/tem_screen/raw/"
mkdir -p $logdir
mkdir -p $pngdir

module load Nextflow/24.10.4

cd /scratch/tem_screen

nextflow run "${workflow_dir}/wfTEM.nf" \
      --logdir $logdir \
      --pngdir $pngdir \
      --rawdir $rawdir \
      --outdir $outdir \
      --container_mrcfile $container_mrcfile \
      --container_imod $container_imod \
      --container_tidyverse $container_tidyverse \
      --dryrun "FALSE" \
      -profile "cluster"     






   eubi to_zarr \
      /scratch/rheinnec/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend.mrc \
      /scratch/rheinnec/alex_omezarr/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend_omezarr \
      --x_unit nm \
      --y_unit nm \
      --x_scale 1.766 \
      --y_scale 1.766








