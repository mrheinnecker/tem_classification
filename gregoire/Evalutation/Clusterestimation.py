# -*- coding: utf-8 -*-
"""
Created on Fri Jun 13 14:49:20 2025

@author: TEAM
"""

from scipy.cluster.hierarchy import dendrogram, linkage
import matplotlib.pyplot as plt
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
import numpy as np
import umap
import os



def main(dimredtype,df):
    X_sizes = df[["size"]]
    X = df.drop(["image_name","size","cellnb"], axis=1).values
    # Assume X is your data matrix (shape: [n_samples, n_features])
    
    # 1. Standardize features (important for PCA)
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # 2. Apply PCA then UMAP to reduce dimensions
    if dimredtype ==0:
        pca = PCA(n_components=0.99)
    if dimredtype ==1:
        pca = PCA(n_components=0.9)
    if dimredtype ==2:
        pca = PCA(n_components=0.9)
    X_pca = pca.fit_transform(X_scaled)
    print(f"Number of components selected: {pca.n_components_}")
    if dimredtype<2:
        umap_model = umap.UMAP(n_neighbors=15, n_components=50,random_state=12)
        X_umap = umap_model.fit_transform(X_pca)
    else:
        X_umap = X_pca
    
    size_scaled = scaler.fit_transform(np.log1p(X_sizes))
    X_umap = scaler.fit_transform(X_umap)
    
    X_final = np.hstack((X_umap, size_scaled))
    
    
    Z = linkage(X_final, method='average')  # or 'average', 'complete', etc.
    
    # Extract linkage distances
    distances = Z[:, 2]
    #print(Z)
    #print(distances)
    # Number of clusters at each step: from n_samples to 1
    n_samples = X_final.shape[0]
    n_clusters = np.arange(1,n_samples)
    distances_rev = distances[::-1]
    #print(distances_rev)
    #print(n_clusters)
    
    cutoff = 70
    lowcutoff = 25
    valid_indices = (n_clusters <= cutoff) & (n_clusters >= lowcutoff)
    
    # Slice the distances and cluster counts
    n_clusters_cut = n_clusters[valid_indices]
    distances_cut = distances_rev[valid_indices]
    #print(distances_cut)
    # Plot
    plt.figure(figsize=(8, 5))
    plt.plot(n_clusters_cut, distances_cut, marker='o')  # reverse distances to match cluster count
    plt.xlabel("Number of clusters")
    plt.ylabel("Linkage distance (to next merge)")
    plt.title("Agglomerative Clustering: Clusters vs. Merge Distance")
    plt.grid(True)
    if dimredtype==0:
        plt.savefig('/g/schwab/GregoireMichelDeletie/slurm_outputs/UMAP.png')
    if dimredtype==1:
        plt.savefig('/g/schwab/GregoireMichelDeletie/slurm_outputs/UMAP_PCA.png')
    if dimredtype==2:
        plt.savefig('/g/schwab/GregoireMichelDeletie/slurm_outputs/PCA.png')
        
dflist=[]
pkl_name="originalDino"
for n in range(1,101):
    df = pd.read_pickle("/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_"+str(n)+f"/{pkl_name}.pkl")
    df['cellnb'] = n
    #print(df.shape)
    dflist.append(df)
df = pd.concat(dflist)
for i in range(1,2):    
    main(i,df)