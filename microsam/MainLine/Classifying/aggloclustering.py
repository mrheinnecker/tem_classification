# -*- coding: utf-8 -*-
"""
Created on Wed Jun  4 14:55:14 2025

@author: TEAM
"""
import pandas as pd
from sklearn.decomposition import PCA
from sklearn.cluster import DBSCAN,HDBSCAN,KMeans, AgglomerativeClustering,OPTICS
from sklearn.preprocessing import StandardScaler
import numpy as np
import umap
from getlabels import get_labeled,matplot_display
import os

model_name="dino"

if model_name=="dino":
    pkl_name="originalDino"
elif model_name=="finetuned":
    pkl_name="teacherStudent"
elif model_name=="finetuned2":
    pkl_name="teacherStudent2"
elif model_name=="SimCLR":
    pkl_name="SimCLR"
dflist=[]
for n in range(1,101):
    df = pd.read_pickle("/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_"+str(n)+f"/{pkl_name}.pkl")
    df['cellnb'] = n
    #print(df.shape)
    dflist.append(df)
df = pd.concat(dflist)
print(df)
#print(df)
#print(df.iloc[12783])
X_sizes = df[["size"]]
X = df.drop(["image_name","size","cellnb"], axis=1)
print(X.columns)
print("Table size :", X.shape)
X=X.values
# Assume X is your data matrix (shape: [n_samples, n_features])

# 1. Standardize features (important for PCA)
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# 2. Apply PCA then UMAP to reduce dimensions
pca = PCA(n_components=0.90)
X_pca = pca.fit_transform(X_scaled)
print(f"Number of components selected: {pca.n_components_}")
umap_model = umap.UMAP(n_neighbors=15, n_components=50,random_state=12)
X_umap = umap_model.fit_transform(X_pca)

size_scaled = scaler.fit_transform(np.log1p(X_sizes))
X_umap = scaler.fit_transform(X_umap)

X_final = np.hstack((X_umap, size_scaled))
print("Table size :", X_final.shape)
# 3. Cluster 
if 0:
    method="KMeans"
    kmeans = KMeans(n_clusters=40, random_state=42)
    labels = kmeans.fit_predict(X_final)
elif 0:
    method="DBSCAN"
    dbscan = DBSCAN(eps=17, min_samples=20)
    labels = dbscan.fit_predict(X_final)
elif 1:
    method="Agglomerative"#Good results
    agg_clustering = AgglomerativeClustering(n_clusters=40,linkage='average',metric='cosine')
    labels = agg_clustering.fit_predict(X_final)
elif 0:
    method="Optics"#Garbage results
    clustering = OPTICS(
    min_samples=50,
    xi=0.015
    )
    labels = clustering.fit_predict(X_final)

elif 0:
    method="HDBSCAN"
    hdbscan = HDBSCAN(
    min_cluster_size=100,       # Large minimum cluster size to force big clusters
    min_samples=100,               # Low min_samples to reduce noise sensitivity
    cluster_selection_epsilon=0, # Larger epsilon to merge nearby clusters aggressively
    metric='euclidean'               # Or 'euclidean' depending on your embeddings
    )
    labels = hdbscan.fit_predict(X_final)
print(method)

#print(len(labels))
#print(f"Cluster labels: {labels}")
val,count = np.unique(labels,return_counts=True)
print(val)  # Cluster assignments for each sample

clustered = df
clustered['cluster']=labels
#print(clustered.keys())
cluster_counts = pd.Series(labels).value_counts().sort_index()

# Convert to DataFrame
df_counts = cluster_counts.reset_index()
df_counts.columns = ['cluster_label', 'count']

print(df_counts)
print("Biggest cluster :", max(count))
print("Small cluster nb (<20) :", np.sum(count<20))

df.to_pickle(rf"/g/schwab/GregoireMichelDeletie/slurm_outputs/cluster_table_{model_name}_{method}_cos.pkl")

df.set_index(["cellnb", "image_name"], inplace=True)


labeled_data=get_labeled();method=""
#matplot_display(df,X_final,labeled_data,12,model=model_name+method)
#matplot_display(df,X_final,labeled_data,42,model=model_name+method)
#matplot_display(df,X_final,labeled_data,45,model=model_name+method)
#matplot_display(df,X_final,labeled_data,69,model=model_name+method)