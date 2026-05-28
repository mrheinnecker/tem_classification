# -*- coding: utf-8 -*-
"""
Created on Thu Jun  5 11:46:46 2025

@author: TEAM
"""

import os
import win32com.client
import pandas as pd
import numpy as np
import shutil

def copy_and_rename(src_path, dest_path):
	# Copy the file
	shutil.copy(src_path, dest_path)

	# Rename the copied file
	new_path = f"{dest_path}/{new_name}"
	shutil.move(f"{dest_path}/{src_path}", new_path)
def create_shortcut(shell, target_path, shortcut_path, working_directory=None, icon_path=None):
    shell = win32com.client.Dispatch("WScript.Shell")
    shortcut = shell.CreateShortCut(shortcut_path)
    shortcut.Targetpath = target_path
    
    if icon_path:
        shortcut.IconLocation = icon_path

    shortcut.save()
    #print(f"Shortcut created: {shortcut_path} -> {target_path}")



clustered = pd.read_pickle(r"Z:\GregoireMichelDeletie\slurm_outputs\cluster_table_finetuned_KNN.pkl")
labels=clustered['prediction'].unique()
shell = win32com.client.Dispatch("WScript.Shell")
for label in labels:
    df_subgroup = clustered[clustered['prediction'] == label]
    print(label)
    if len(df_subgroup)<5:
        continue
    os.mkdir(rf'Z:\GregoireMichelDeletie\slurm_outputs\clusters\{label}')
    sampled = df_subgroup.sample(n=min(100, len(df_subgroup)), random_state=42)
    for a, organelle in sampled.iterrows():
        #print(a)
        #print(f'Z:\GregoireMichelDeletie\slurm_outputs\cell_nb_{organelle["cellnb"]}\maskstore\{organelle["image_name"]}')
        #print(rf'Z:\GregoireMichelDeletie\slurm_outputs\cell_nb_{a[0]}\maskstoreContextExpanded\{a[1]}')
        shutil.copy(rf'Z:\GregoireMichelDeletie\slurm_outputs\cell_nb_{a[0]}\maskstoreContextExpanded\{a[1]}', rf'Z:\GregoireMichelDeletie\slurm_outputs\clusters\{label}\cell_{a[0]}_{a[1]}')
