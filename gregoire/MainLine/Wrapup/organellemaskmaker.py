# -*- coding: utf-8 -*-
"""
Created on Thu Jul 31 13:45:08 2025

@author: TEAM
"""

import os
import pandas as pd
import numpy as np
from PIL import Image
import shutil

MODEL_TYPE="vit_b"

clustered = pd.read_pickle(r"/g/schwab/GregoireMichelDeletie/slurm_outputs/cluster_table_dino_KNN.pkl")
labels=clustered['prediction'].unique()
clustered.reset_index(inplace=True)
print(clustered)
cells=clustered['cellnb'].unique()
for n in cells:
    cell_df=clustered[clustered['cellnb'] == n]
    path = f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/mask_"+MODEL_TYPE+"_merged.png"
    if not os.path.exists(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/labeledMasks"):
        os.mkdir(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/labeledMasks")
    masks=np.asarray(Image.open(path))
    for label in labels:
        df_subgroup = cell_df[cell_df['prediction'] == label]['image_name']
        nbs=[int(imgn[len("organelle_"):-len(".png")]) for imgn in df_subgroup]
        print(nbs)
        newmask = np.zeros(masks.shape)
        newmask[np.isin(masks,nbs)]=masks[np.isin(masks,nbs)]
        if np.isin(masks,nbs).any():
            newmask=Image.fromarray(newmask.astype(np.uint16))
            newmask.save(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/labeledMasks/mask_{label}.png")
        else:
            if os.path.isfile(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/labeledMasks/mask_{label}.png"):
                os.remove(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/labeledMasks/mask_{label}.png")
        
