# -*- coding: utf-8 -*-
"""
Created on Tue Jul  8 10:52:00 2025

@author: TEAM
"""

import os
import pandas as pd
import numpy as np
import sys
from sklearn.metrics import confusion_matrix, normalized_mutual_info_score, adjusted_rand_score,ConfusionMatrixDisplay
from scipy.optimize import linear_sum_assignment
import matplotlib.pyplot as plt

current_dir = os.path.dirname(__file__)
utils_dir = os.path.join(current_dir, '..', 'MainLine','Classifying')
sys.path.append(os.path.abspath(utils_dir))
print(sys.path)
from getlabels import get_labeled


"dino","finetuned","finetuned2","SimCLR"
"KMeans","Agglomerative"
model_name="dino"
method="Agglomerative"
#clustered = pd.read_pickle(r"Z:\GregoireMichelDeletie\slurm_outputs\cluster_table.pkl")
clustered = pd.read_pickle(rf"/g/schwab/GregoireMichelDeletie/slurm_outputs/cluster_table_{model_name}_{method}_cos.pkl")
clustered.set_index(["cellnb", "image_name"], inplace=True)

Solutions=get_labeled()
#print(clustered)
#print(clustered)
affectations=[]
for key in Solutions.keys():
    affectations.append([])
    for a,b in Solutions[key]:
        #print(a,b)
        #print((a,f"organelle_{b}.png"))
        cluster=clustered.loc[(int(a),f"organelle_{b}.png")]['cluster']
        affectations[-1].append(int(cluster))
#print(affectations)

def evaluate_sparse_clustering(true_cluster_data):
    """
    Evaluate sparse clustering where true labels are limited and only a subset is known.
    
    Parameters:
    - true_cluster_data: list of lists.
        Each inner list contains predicted cluster IDs belonging to one true class.
    
    Outputs:
    - Prints confusion matrix, best label mapping accuracy, NMI, ARI, and purity.
    """
    true_labels = []
    predicted_labels = []

    # Build full label vectors
    for true_id, predicted_list in enumerate(true_cluster_data):
        true_labels.extend([true_id] * len(predicted_list))
        predicted_labels.extend(predicted_list)

    if len(true_labels) == 0:
        print("No data to evaluate.")
        return

    # Create confusion matrix with all predicted labels (may be sparse & high-ID)
    unique_preds = sorted(set(predicted_labels))
    pred_to_idx = {label: i for i, label in enumerate(unique_preds)}
    y_pred_idx = [pred_to_idx[p] for p in predicted_labels]

    cm = confusion_matrix(true_labels, y_pred_idx)
    print("Results for ",model_name,method)
    
    row_sums = cm.sum(axis=1, keepdims=True)
    cm = 100 * cm / row_sums
    np.nan_to_num(cm,copy=False)
    #print("Confusion Matrix (true rows × predicted columns):")
    #print(cm)

    # Hungarian algorithm: maximize alignment
    cost_matrix = -cm  # we want to maximize match
    row_ind, col_ind = linear_sum_assignment(cost_matrix)

    # Create mapping from predicted cluster index to true label
    best_mapping = dict(zip(col_ind, row_ind))
    mapped_preds = [best_mapping.get(i, -1) for i in y_pred_idx]

    # Compute metrics
    acc = np.mean([t == p for t, p in zip(true_labels, mapped_preds)])
    purity = np.sum(np.max(cm, axis=1)) / np.sum(cm)
    nmi = normalized_mutual_info_score(true_labels, y_pred_idx)
    ari = adjusted_rand_score(true_labels, y_pred_idx)

    #print(cm)
    known_labels = list(Solutions.keys())
    known_indices = [row_ind[i] for i in col_ind if row_ind[i] < len(known_labels)]
    
    # Create new confusion matrix with known predictions + one 'Other' column
    new_cm = np.zeros((len(known_labels)+1 , len(known_labels) + 1), dtype=int)  # +1 for 'Other'
    
    # Build inverse mapping: pred_cluster → mapped_true_label
    inv_map = {v: k for k, v in best_mapping.items()}
    num_known = len(known_labels)

    for pred_idx in range(cm.shape[1]):
        for true_idx in range(cm.shape[0]):
            # Determine mapped true and predicted indices
            mapped_pred = best_mapping.get(pred_idx, -1)
            mapped_true = true_idx if true_idx < num_known else -1
    
            row = mapped_true if mapped_true != -1 else num_known  # "Other" row
            col = mapped_pred if mapped_pred != -1 and mapped_pred < num_known else num_known  # "Other" column
    
            new_cm[row, col] += cm[true_idx, pred_idx]
    print(new_cm.shape)
    
    # Display updated confusion matrix
    display_labels = known_labels + ['Other']
    disp = ConfusionMatrixDisplay(confusion_matrix=new_cm, display_labels=display_labels)
    disp.plot(cmap=plt.cm.Blues, values_format=".0f")
    plt.title(f"Confusion Matrix - {model_name}")
    plt.xticks(rotation=90)
    plt.tight_layout()
    plt.savefig(f'/g/schwab/GregoireMichelDeletie/slurm_outputs/ConfMatrix_{model_name}_cos_unsupervised.png')
    plt.clf()
    
    print("\nEvaluation Metrics after Hungarian alignement:")
    print(f"  Accuracy : {acc:.2f}")
    print(f"  Purity: {purity:.2f}")
    print(f"  NMI: {nmi:.2f}")
    print(f"  ARI: {ari:.2f}")

evaluate_sparse_clustering(affectations)