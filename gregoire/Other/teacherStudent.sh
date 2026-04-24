#!/bin/bash
#SBATCH --partition=gpu
#SBATCH --job-name=finetune
#SBATCH --output=TS.txt
#SBATCH --ntasks-per-node=4     # Number of GPUs per node (e.g., 4 GPUs)
#SBATCH --gres=gpu:4
#SBATCH --cpus-per-task=8
#SBATCH -N 1
#SBATCH -t 10:00:00
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
conda activate dinov2

export NCCL_P2P_DISABLE=1
export NCCL_IB_DISABLE=1          # disables InfiniBand (if irrelevant)
export NCCL_SOCKET_IFNAME=^lo,docker
export NCCL_DEBUG=INFO
export NCCL_SHM_DISABLE=1
export NCCL_IB_DISABLE=1
export NCCL_P2P_DISABLE=1
export NCCL_IGNORE_DISABLED_ECC=1  # (less common, may help in edge cases)
export MASTER_ADDR=$(scontrol show hostname $SLURM_NODELIST | head -n1)
export MASTER_PORT=12345  # You can choose any free port number
export CUDA_LAUNCH_BLOCKING=1


# Run your script
srun --ntasks=4 bash -c 'export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID;  python /g/schwab/GregoireMichelDeletie/Codes/teacherStudent.py'
