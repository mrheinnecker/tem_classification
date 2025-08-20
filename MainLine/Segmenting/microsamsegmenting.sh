#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --job-name=microsam
#SBATCH --array=102-103     # nb of parallel tasks (both bounds included)
#SBATCH --output=test_%a.txt
#SBATCH --cpus-per-task=1
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

# Activate the conda environment required for your calculations
conda deactivate
conda activate micro-sam-env


# Run your script
python /g/schwab/GregoireMichelDeletie/Codes/MainLine/Segmenting/microsamsegmenting.py $SLURM_ARRAY_TASK_ID
