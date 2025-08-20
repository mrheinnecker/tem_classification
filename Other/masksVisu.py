# -*- coding: utf-8 -*-
"""
Created on Thu May 15 09:58:28 2025

@author: TEAM
"""

import numpy as np
from PIL import Image
import cv2
#from unmask import masksplit
import zarr, os, pprint
import napari
from maskclean import clean_masks,merge_masks


tilenb = 2
MODEL_TYPES=["vit_b","vit_b_em_organelles","vit_b_lm"]
paths=["Z:\GregoireMichelDeletie\mask_"+MODEL_TYPE+"_merged.png" for MODEL_TYPE in MODEL_TYPES]
path='Z:\Karel\Mobie_project_dinoflagellate\data\VSM20_A1_AM1\images\ome-zarr\VSM20_A1_AM1_014.ome.zarr'
#path = 'Z:\\Gregoire MichelDeletie\VSM20_A1_AM1_001.ome.zarr'
dataset = zarr.open_group(path, mode = 'r')
img = dataset["s3"]

image = np.asarray(img)
labels= []
for loc in paths :
    label = np.asarray(Image.open(loc)) 
    if 'big' in loc:
        label=label[::2,::2]
    print('Number of Masks : ',len(np.unique(label)))
    labels.append(label)
#mask = Image.fromarray(instances.astype(np.uint16))
# Save the image
#mask.save("C:\\Users\\TEAM\\Desktop\\Gregoire\\mask.png")
# Visualize the image and corresponding instance segmentation result.
v = napari.Viewer()
v.add_image(image, name="Image")
for label,MODEL_TYPE in zip(labels,MODEL_TYPES):
    v.add_labels(label, name=MODEL_TYPE+".png")

napari.run()