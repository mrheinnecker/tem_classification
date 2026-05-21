#!bin/bash

workflow_dir="$1"

workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"

container_mrcfile="/g/schwab/marco/container_legacy/py_mrcfile.sif"
container_imod="/g/schwab/marco/container_legacy/EMBL_IMOD_5.1.0-foss-2023a-CUDA-12.1.1.sif"
container_tidyverse="/g/schwab/marco/container_devel/probeDesign_rtool.sif"
container_eubi="/g/schwab/marco/container_devel/eubibridge.sif"

timestamp=$(date +%Y-%m-%d_%H-%M)


main_dir="/scratch/rheinnec/tem_screen"
#main_dir="/g/schwab/tem_screen"


logdir="${main_dir}/logs/wfTEM_${timestamp}"
pngdir="${main_dir}/pngs"
outdir="${main_dir}/processed"
rawdir="${main_dir}/raw/"
mkdir -p $logdir
mkdir -p $pngdir

module load Nextflow/24.10.4

cd /scratch/rheinnec/tem_screen

nextflow run "${workflow_dir}/wfTEM.nf" \
      --logdir $logdir \
      --pngdir $pngdir \
      --rawdir $rawdir \
      --outdir $outdir \
      --container_mrcfile $container_mrcfile \
      --container_imod $container_imod \
      --container_tidyverse $container_tidyverse \
      --container_eubi $container_eubi \
      --container_mc "/g/schwab/marco/container_devel/EMBL_mc_2024-05-03T11-21-07Z.sif" \
      --dryrun "TRUE" \
      -profile "cluster" \
      -resume






singularity shell -B /scratch -B /g -B /home "/g/schwab/marco/container_devel/eubibridge.sif"

   eubi to_zarr \
      /scratch/rheinnec/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend.mrc \
      /scratch/rheinnec/245756_S2_Cut2_c019_116114649_KRI_10to40_20230802_PM_01_epo_02_P1_correctionblend_omezarr6 \
      --x_unit nm \
      --y_unit nm \
      --x_scale 1.766 \
      --y_scale 1.766 \
      --dimension_order xyzct \
      --squeeze True \
      --save_omexml True \
      --zar_format 3 \
      --auto_chunk True
      
            --metadata_reader bioio \





singularity shell -B /scratch -B /g -B /home "/scratch/rheinnec/container_devel/py_temscreen.sif"

  python /g/schwab/marco/repos/tem_classification/scripts_marco/crop_omezarr_by_mask.py \
    --input "/g/schwab/tem_screen/processed/245756_Q4_Cut1_c039_116114998_NAP_10to40_20240415_AM_02_epo_01_P1/245756_Q4_Cut1_c039_116114998_NAP_10to40_20240415_AM_02_epo_01_P1_correctionblend.mrc" \
    --output "/scratch/rheinnec/cropped_omezarr.ome.zarr" \
    --foreground "darker" \
    --threshold "otsu" \
    --sigma 5 \
    --padding 1000 \
    --min-object-size 50000 \
    --save-mask \
    --qc-png "/g/schwab/marco/cropped_omezarr.png" \
    --segmentation-mode foreground \
    --threshold-scale 1


nextflow run


## copy something to s3 bucket

mc cp /g/schwab/marco/table.pdf s3embl/temscreen



singularity shell -B /scratch -B /g -B /home "/g/schwab/marco/container_devel/EMBL_mc_2024-05-03T11-21-07Z.sif"


cd /scratch/rheinnec/tem_screen

nextflow run /g/schwab/marco/repos/tem_classification/test_mc.nf \
  --container_mc "/g/schwab/marco/container_devel/EMBL_mc_2024-05-03T11-21-07Z.sif"




