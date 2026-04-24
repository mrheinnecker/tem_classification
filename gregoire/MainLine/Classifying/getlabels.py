# -*- coding: utf-8 -*-
"""
Created on Thu Jul 10 14:03:29 2025

@author: TEAM
"""
import os
import numpy as np
import umap
import matplotlib.pyplot as plt

def get_labeled():
    solutions={
    }
    for y in os.listdir(r"/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data"):
        if not os.path.isdir(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data",y)):
            continue
        solutions[y]=[]
        for x in os.listdir(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data",y)):
            if x.endswith(".png"):
                solutions[y].append(x[1:-4].split("o"))
    print(solutions.keys())
    return solutions

def matplot_display(df,X_final,solutions=None,seed=45,model=''):
    #print(solutions)
    umap_display = umap.UMAP(n_neighbors=15, n_components=2,random_state=seed,min_dist=0.)
    X_display = umap_display.fit_transform(X_final)
    #print(len(X_display[:,0]),len(X_display[:,1]))
    df['x']=X_display[:,0]
    df['y']=X_display[:,1]
    if solutions is None:
        cmap=plt.cm.get_cmap('hsv', max(df['cluster']))
        plt.scatter(df['x'],df['y'],s=0.5,c=cmap(df['cluster']))
        plt.savefig(f'/g/schwab/GregoireMichelDeletie/slurm_outputs/clusterAgno_{seed}_{model}.png')
        print("Figure was saved successfully")
    else:
        plt.scatter(df['x'],df['y'],s=0.5,c='black', label="other")
        cmap=plt.cm.get_cmap('hsv', len(solutions)+1)
        for i,key in enumerate(solutions.keys()):
            list_of_indices=solutions[key]
            list_of_indices=[(int(a),f"organelle_{b}.png") for a,b in list_of_indices]
            #print(list_of_indices)
            #print(df)
            new_df = df.loc[list_of_indices,:]
            #print(f"{key} is represented in {cmap(i)}")
            plt.scatter(new_df['x'],new_df['y'],s=0.5,c=cmap(i), label=key)
        plt.legend(["Other"]+list(solutions.keys()))
            
        plt.savefig(f'/g/schwab/GregoireMichelDeletie/slurm_outputs/clusterVisu_{seed}_{model}.png')
        print(f"Figure was saved successfully : clusterVisu_{seed}_{model}.png")