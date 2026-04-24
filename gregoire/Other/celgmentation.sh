#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --job-name=microsam
#SBATCH --output=test.txt
#SBATCH -N 1
#SBATCH -t 00:10:00
#SBATCH --gres=gpu:1
#SBATCH --mem=20000

# Load and activate Conda
module purge
# Load the Anaconda module that matches your needs
module load Mamba/4.14.0-0
# Activate conda in the current environment
source <(conda shell.bash hook)

# Activate the conda environment required for your calculations
conda activate micro-sam-env


# Run your script
python /g/schwab/GregoireMichelDeletie/Codes/celgmentation.py