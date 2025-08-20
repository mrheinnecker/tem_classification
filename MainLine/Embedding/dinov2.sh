#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --job-name=dinov2
#SBATCH --array=102-103    # nb of parallel tasks (both bounds included)
#SBATCH --output=dino_%a.txt
#SBATCH -N 1
#SBATCH -t 00:10:00
#SBATCH --gres=gpu:1
#SBATCH --mem=20000

# Load and activate Conda
module purge
# Load the Anaconda module that matches your needs
module load Mamba/4.14.0-0
# Activate conda in the current environment
source ~/.bashrc
initialize_conda
# source <(conda shell.bash hook)
conda deactivate
# Activate the conda environment required for your calculations
conda activate micro-sam-env

# Run your script
python /g/schwab/GregoireMichelDeletie/Codes/MainLine/Embedding/dinov2.py $SLURM_ARRAY_TASK_ID
