Order of execution for Mainline:
Segmenting/microsamsegmenting*
Segmenting/maskmerge*
Extraction/getimages*
Embedding/dinov2*
Clustering/knn or aggloclustering
Wrapup/organellemaskmaker

Programs with an * are meant to be executed on the embl slurm server (cloud) by connecting to it (ssh username@cluster.embl.de) and executing the .sh file of the same name. This allows to parallelise as many image processing as you want by editing the array field (1 or 1-10 or 2,3,5,7).
You will need to set up an environement on the slurm server containing all the used libraries. To use conda, change the .bashrc by copying mine (cp path/bash.txt .bashrc) or refer to the IT recommendation. It is not recommended to use the 'conda init' line even when it is suggested by conda. When installing packages with conda, be sure to use free channels like conda-forge to avoid licencing issues (should be blocked anyways).

All programs were made to be run on the slurm server and thus the paths are absolute for the slurm server. They are also written with linux separators.