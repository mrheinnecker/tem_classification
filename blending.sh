#!bin/bash

# login with your credentials
ssh login1.cluster.embl.de

# decide if you want to:
# OPTION 1: run interactively (gives you the chance to overlook the process - but you need to keep the terminal open)
# OPTION 2: run as batch job (you can just shut down everything and leave)


## OPTION 1:
# allocate clusternode for some hours (can be shorter if few images only) 
# ... can take some minutes until resources are allocated
srun -p htc --time=0-03:00:00 --ntasks-per-node 64 --mem 32G --pty bash

# execute blending workflow (adjust path to your local repo clone!!!!!!!)
workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"
bash "${workflow_dir}/main.sh" $workflow_dir 


## OPTION 2:
workflow_dir="/g/schwab/marco/repos/tem_classification/scripts_marco"
sbatch -J "wfTEM" -t 3:00:00 --mem 2000 -e "/scratch/tem_screen/log.txt" -o "/scratch/tem_screen/log.out" --wrap="bash "${workflow_dir}/main.sh" $workflow_dir"

