# -*- coding: utf-8 -*-
"""
Created on Tue May 27 12:28:29 2025

@author: TEAM
"""

import numpy as np
from PIL import Image
import cv2
import zarr, os, pprint
import napari
from micro_sam.automatic_segmentation import get_predictor_and_segmenter, automatic_instance_segmentation

MODEL_TYPE = "vit_b"
tilenb = 3

path = '/g/schwab/Karel/Mobie_project_dinoflagellate/data/VSM20_A1_AM1/images/ome-zarr/VSM20_A1_AM1_014.ome.zarr'
dataset = zarr.open_group(path, mode = 'r')

print('image opened')

img = dataset["s3"]

image = np.asarray(img)

print('Ready to save')

tosave = Image.fromarray(image)
tosave.save("/g/schwab/GregoireMichelDeletie/merged.png")