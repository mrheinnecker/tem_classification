#!bin/bash


container_mrcfile="/scratch/rheinnec/container_devel/py_mrcfile.sif"
container_imod="/scratch/rheinnec/container_devel/EMBL_IMOD_5.1.0-foss-2023a-CUDA-12.1.1.sif"
container_tidyverse="/g/schwab/marco/container_legacy/probeDesign_rtool.sif"

workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"
rawdir="/scratch/rheinnec/tem_screen/raw/"
timestamp=$(date +%Y-%m-%d_%H-%M)

logdir="/scratch/rheinnec/runs/wfTEM_${timestamp}"
pngdir="/g/schwab/marco/wfTEM_pngs"
mkdir -p $logdir
mkdir -p $pngdir

module load Nextflow/24.10.4

cd /scratch/rheinnec

nextflow run "${workflow_dir}/wfTEM.nf" \
      --logdir $logdir \
      --pngdir $pngdir \
      --rawdir $rawdir \
      --container_mrcfile $container_mrcfile \
      --container_imod $container_imod \
      --container_tidyverse $container_tidyverse \
      -profile "cluster" \
      -resume      















############## old


singularity shell -B /home -B /scratch -B /g /scratch/rheinnec/container_devel/py_mrcfile.sif


python3 /g/schwab/marco/repos/tem_classification/scripts_marco/process_images.py \
    -i "/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008_blend.mrc" \
    -o"/g/schwab/marco/test_tem8.png"


module load Nextflow/24.10.4

module load IMOD


img_test="/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008"


justblend $img_test



raw_mrc="/g/schwab/marco/container_legacy/work/a9/131dc462a40bc35a6643a60ee1ca4d/245756_G1_Cut1_117659905_BAR_20to200_20240321_AM_01_epo_03_P1_c010_blend.mrc"
raw_pl="/g/schwab/marco/container_legacy/work/a9/131dc462a40bc35a6643a60ee1ca4d/245756_G1_Cut1_117659905_BAR_20to200_20240321_AM_01_epo_03_P1_c010_blend.pl"

blendmont -imi "${raw_mrc}" -pli "${raw_pl}" -imo /g/schwab/marco/testblend2.mrc -int 1 -roo /scratch/rheinnec/test1 -sloppy

blendmont -imi 245756_G1_Cut1_117659905_c001_blend.mrc -pli 245756_G1_Cut1_117659905_c001.pl -imo "245756_G1_Cut1_117659905_c001_correctionblend.mrc" -int 1 -roo test1 -sloppy






    outname="${raw_mrc%.mrc}"

    module load IMOD

    blendmont -imi "${raw_mrc}" -pli "${raw_pl}" -imo "${outname}" -int 1 -roo test1 -sloppy







