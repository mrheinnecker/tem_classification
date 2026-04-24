# -*- coding: utf-8 -*-
"""
Created on Tue Jun 17 14:45:56 2025

@author: TEAM
"""

import matplotlib.pyplot as plt
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import HDBSCAN
import numpy as np
import umap

df = pd.read_pickle("/g/schwab/GregoireMichelDeletie/slurm_outputs/cluster_table.pkl")
df = df[['cluster','cellnb','image_name']]
print(df)
table = pd.pivot_table(df, values='image_name', index=['cellnb'],
                       columns=['cluster'], aggfunc="count",
    fill_value=0)
print(table)

np.random.seed(42)

X = np.log1p(table)
X = StandardScaler().fit_transform(X)
umap_model = umap.UMAP(n_components=2)
X_umap = umap_model.fit_transform(X)

print("HDBSCAN")
hdbscan = HDBSCAN(
    min_cluster_size=3,
    cluster_selection_epsilon=0,
    metric='euclidean'
    )
labels = hdbscan.fit_predict(X_umap)


plt.figure(figsize=(8, 5))
plt.scatter(X_umap[:, 0], X_umap[:, 1],c=labels, marker='o')
plt.xlabel("Umap1")
plt.ylabel("Umap2")
plt.title("Umap of cells")
plt.grid(True)

plt.savefig('/g/schwab/GregoireMichelDeletie/slurm_outputs/cellzones.png')