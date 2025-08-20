#!/bin/bash

## run gregoires full workflow

sbatch /g/schwab/marco/repos/tem_classification/MainLine/Segmenting/microsamsegmenting.sh

sbatch /g/schwab/marco/repos/tem_classification/MainLine/Segmenting/maskmerge.sh

sbatch /g/schwab/marco/repos/tem_classification/MainLine/Extraction/getimages.sh

sbatch /g/schwab/marco/repos/tem_classification/MainLine/Embedding/dinov2.sh


module load Mamba/4.14.0-0
# Activate conda in the current environment

source <(/g/easybuild/x86_64/Rocky/8/znver2/software/Mamba/4.14.0-0/bin/conda shell.bash hook)

conda activate /g/schwab/marco/conda_microsam


## move to directory where scripts are in
cd /g/schwab/marco/repos/tem_classification/MainLine/Classifying

python3


