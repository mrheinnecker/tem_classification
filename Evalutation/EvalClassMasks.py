# -*- coding: utf-8 -*-
"""
Created on Fri Aug  1 10:22:35 2025

@author: TEAM
"""
import numpy as np
from PIL import Image
import scipy
import sys
import pandas as pd
import os.path
import matplotlib.pyplot as plt


MODEL_TYPE="vit_b"

precision = []
maxrecall = []
recall = []


for n in range(100):
    n=str(14)
    karelpath="/g/schwab/Karel/Mobie_project_dinoflagellate/Micro-sam/Organelle_P_Protoperidinium/VSM20_A1_AM1_"+"0"*(3-len(n))+n+"_bin10.tif"
    karelpath="/g/schwab/Karel/Mobie_project_dinoflagellate/Micro-sam/Chloroplast_segmentation/VSM20-A1-AM1-chloroplast/VSM20_A1_AM1_"+"0"*(3-len(n))+n+"_chl.tif"
    #path = '/g/schwab/Karel/Mobie_project_dinoflagellate/data/VSM20_A1_AM1/images/ome-zarr/VSM20_A1_AM1_'+"0"*(3-len(n))+n+'.ome.zarr'
    fullmask =np.asarray(Image.open("/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_"+n+"/mask_vit_b_merged.png"))
    evalpath="/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_"+n+"/labeledMasks/mask_Chloroplasts.png"
    full = fullmask>0.5
    if os.path.isfile(karelpath):
        print("FOUUUUNNDDDD ITTTTT")
        trueMask=np.asarray(Image.open(karelpath))
        upscale=[fullmask.shape[i]/trueMask.shape[i] for i in range(len(fullmask.shape))]
        trueMask=scipy.ndimage.zoom(trueMask,upscale, order=3)
        true = trueMask>0.5
    else:
        true=np.zeros(full.shape)>0.5
    if os.path.isfile(evalpath):
        instances =np.asarray(Image.open(evalpath))
        test = instances>0.5
    else:
        test=np.zeros(full.shape)>0.5


    Total=sum(sum(true | test))
    if Total==0:
        continue
    Pos=sum(sum(true))
    Selected=sum(sum(test))
    #FalsePos=sum(sum(test & ~true))
    TruePos=sum(sum(test & true))
    #FalseNeg=sum(sum(~test & true))
    Segmented=sum(sum(full & true))

    #print(n+"Chloroplast area",Total)
    #print(n+"Of which were segmented :",Segmented/Total)
    if Pos>0:
        maxrecall.append(Segmented/Pos)
        recall.append(TruePos/Pos)
    #print(n+"Precision :",TruePos/Selected)
    if Selected>0:
        precision.append(TruePos/Selected)
    print(n)
    Image.fromarray(true.astype(np.uint8)).save("/g/schwab/GregoireMichelDeletie/true.png")
    Image.fromarray(test.astype(np.uint8)).save("/g/schwab/GregoireMichelDeletie/test.png")
    merge=np.zeros(full.shape)
    merge[true]=1
    merge[test]=2
    merge[test&true]=3
    
    
    Image.fromarray(merge.astype(np.uint8)).save("/g/schwab/GregoireMichelDeletie/merge.png")
    
    
    break
print(recall)
print(maxrecall)
print(precision)
data = [recall, maxrecall, precision]

#plt.boxplot(data, labels=['Recall', 'Max Recall', 'Precision'])
#plt.ylabel('Values')
#plt.savefig("/g/schwab/GregoireMichelDeletie/slurm_outputs/Eval_P_cos.png")


