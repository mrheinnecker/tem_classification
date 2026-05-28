#!/bin/bash
#SBATCH --job-name=clustering
#SBATCH --output=test.txt
#SBATCH -N 1
#SBATCH -t 00:15:00
#SBATCH --mem=16000

# Load and activate Conda
module purge
# Load the Anaconda module that matches your needs
module load Mamba/4.14.0-0
# Activate conda in the current environment
source ~/.bashrc
initialize_conda

# Activate the conda environment required for your calculations
conda deactivate
# Activate the conda environment required for your calculations
conda activate micro-sam-env
which python

# Run your script
python /g/schwab/GregoireMichelDeletie/Codes/MainLine/Segmenting/aggloclustering.py