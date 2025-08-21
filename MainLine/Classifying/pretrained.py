# -*- coding: utf-8 -*-
"""
Created on Mon Jul 28 10:33:01 2025

@author: TEAM
"""

import pandas as pd
from sklearn.decomposition import PCA
from sklearn.cluster import DBSCAN,HDBSCAN,KMeans, AgglomerativeClustering,OPTICS
from sklearn.neighbors import KNeighborsClassifier,LocalOutlierFactor
from sklearn.model_selection import train_test_split,StratifiedKFold
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import balanced_accuracy_score,confusion_matrix,ConfusionMatrixDisplay
import numpy as np
import umap
import os
import matplotlib.pyplot as plt
import pickle as pkl



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

for n in range(102,103):
    df = pd.read_pickle(f"/g/schwab/GregoireMichelDeletie/slurm_outputs/cell_nb_{n}/{pkl_name}.pkl")
    df['cellnb'] = n
    #print(df.shape)
    dflist.append(df)

df = pd.concat(dflist)
#print(df)
#print(df)
#print(df.iloc[12783])
df.set_index(["cellnb", "image_name"], inplace=True)



df[["size"]]=np.log1p(df[["size"]])

sizeid = df.columns.tolist().index("size")

X=df.values

with open("/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data/scalerparams.pkl", "rb") as f:
    scaler=pkl.load(f)
X_scaled = scaler.transform(X)

#print(X_scaled)

size_scaled=X_scaled[:,[sizeid]]
X_scaled=np.delete(X_scaled, sizeid, axis=1)


with open("/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data/PCAparams.pkl", "rb") as f:
    pca=pkl.load(f)

#print("size of save :",os.path.getsize("/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data/PCAparams.pkl"))  # Should print a positive number


X_pca = pca.transform(X_scaled)
#print(f"Number of components selected: {pca.n_components_}")
#umap_model = umap.UMAP(n_neighbors=15, n_components=50,random_state=12)
#X_umap=X_pca
#X_umap = umap_model.fit_transform(X_pca)


#print(X_pca.shape,size_scaled.shape)

X_final = np.hstack((X_pca, size_scaled))

#print(X_final)
#print("Table size :", X_final.shape)


# 3. Cluster 
df_final=pd.DataFrame(X_final, index=df.index)




labeled=pd.read_pickle(rf"/g/schwab/GregoireMichelDeletie/slurm_outputs/labeled_data/knnreference.pkl")
print(labeled)
unlabeled=df_final
method="KNN"


#plt.plot([x/len(size_scaled) for x in range(len(size_scaled))], sorted(size_scaled), color='b')
#plt.plot([x/len(size_scaled[df_final['cluster'].notna()]) for x in range(len(size_scaled[df_final['cluster'].notna()]))], sorted(size_scaled[df_final['cluster'].notna()]), color='r')
#Sthreshold = np.percentile(size_scaled[df_final['cluster'].notna()], 5)
#print("Size threshold : ",Sthreshold)
#plt.plot([0,1],[Sthreshold,Sthreshold],color='g')

#plt.savefig(f'/g/schwab/GregoireMichelDeletie/slurm_outputs/SizeRep.png')
#plt.clf()
#print(f"Figure was saved successfully : SizeRep.png")



#labeled=labeled[size_scaled[df_final['cluster'].notna()]>Sthreshold]
#unlabeled=unlabeled[size_scaled[~df_final['cluster'].notna()]>Sthreshold]

n=5

X=labeled.drop(['cluster'],axis=1).values
y=labeled['cluster'].values

#print("X :",len(X))

K=5


clf = KNeighborsClassifier(n_neighbors=K,metric="cosine")
clf.fit(X, y)
Xu=unlabeled.values
unlabeled["prediction"]=clf.predict(Xu)



# Noise Detection
distances, indices = clf.kneighbors(Xu)
average_distances = distances.mean(axis=1)

distances0, indices = clf.kneighbors(X)
average_distances0 = distances0.mean(axis=1)

dist_threshold = np.percentile(average_distances0,95)

unlabeled.loc[average_distances > dist_threshold, "prediction"] = "None"

print(labeled.columns)

size_threshold = np.percentile(labeled[len(labeled.columns)-2].values,5)

unlabeled.loc[unlabeled[len(labeled.columns)-2].values < size_threshold, "prediction"] = "None"

'''
distances, indices = clf.kneighbors(X)

# Compute average distance for each test point
average_distances2 = distances2.mean(axis=1)
'''

print(unlabeled["prediction"].value_counts())


unlabeled.to_pickle(r"/g/schwab/GregoireMichelDeletie/slurm_outputs/pretrained_output.pkl")