#!bin/bash

singularity shell -B /home -B /scratch -B /g /scratch/rheinnec/container_devel/py_mrcfile.sif


python3 /g/schwab/marco/repos/tem_classification/scripts_marco/process_images.py \
    -i "/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008_blend.mrc" \
    -o"/g/schwab/marco/test_tem8.png"


module load Nextflow/24.10.4

module load IMOD


img_test="/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008"


justblend $img_test

blendmont -imi "${img_test}.mrc" -pli "${img_test}.pl" -imo /g/schwab/marco/testblend.mrc -int 1 -roo /scratch/rheinnec/test1 -sloppy


raw_mrc="/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008.mrc"
raw_pl="/scratch/rheinnec/tem_screen/245756_A5_Cut1_116114425_TAL_10to40_20230617_AM_01_epo_01_P1/245756_A5_Cut1_1161114425_c008.pl"

workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"
rundir="/scratch/rheinnec/wfTEM_test2"
mkdir -p $rundir

module load Nextflow/24.10.4

nextflow run "${workflow_dir}/wfTEM.nf" \
      --logdir $rundir \
      --raw_mrc $raw_mrc \
      --raw_pl $raw_pl \
      -profile "cluster" 



    outname="${raw_mrc%.mrc}"

    module load IMOD

    blendmont -imi "${raw_mrc}" -pli "${raw_pl}" -imo "${outname}" -int 1 -roo test1 -sloppy







