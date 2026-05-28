# -*- coding: utf-8 -*-
"""
Created on Mon Jun  2 11:28:00 2025

@author: TEAM
"""

import numpy as np
from PIL import Image
import zarr
from micro_sam.automatic_segmentation import get_predictor_and_segmenter, automatic_instance_segmentation
from micro_sam.prompt_based_segmentation import segment_from_points
import cv2


path = '/g/schwab/Karel/Mobie_project_dinoflagellate/data/VSM20_A1_AM1/images/ome-zarr/VSM20_A1_AM1_019.ome.zarr'
dataset = zarr.open_group(path, mode = 'r')

MODEL_TYPE = "vit_b"
tilenb = 1
img = np.asarray(dataset["s6"])
print(img.shape)
#img = cv2.resize(img, (150, 150))
print(img)
h,w=img.shape



def largest_component(mask):
    """
    Find the largest connected component in the binary mask and fill its holes.

    Args:
        mask (np.ndarray): Binary mask (2D array) with values 0 and 1 (or bool).

    Returns:
        np.ndarray: Binary mask of the largest component with holes filled.
    """
    # Ensure mask is uint8
    mask_uint8 = (mask > 0).astype(np.uint8)
    # Find connected components
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask_uint8, connectivity=4)
    if num_labels <= 1:
        # No components found (only background)
        return np.zeros_like(mask_uint8)
    # Largest component label (excluding background)
    largest_label = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    # Mask for largest component
    largest_comp_mask = (labels == largest_label).astype(np.uint8)
    return largest_comp_mask

def largest_component_filled(mask):
    new = largest_component(mask)
    inv_mask = 1-new
    inv_filled = largest_component(inv_mask)
    return 1-inv_filled


for i in range(tilenb):
    for j in range(tilenb):
        #print(f"Chunk size: {img.chunks}")
        
        image = np.asarray(img[max(0,int(i*h/tilenb-20)):min(h,int((i+1)*h/tilenb+20)),max(0,int(j*w/tilenb-20)):min(w,int((j+1)*w/tilenb+20))])
        
        
        # Load the Segment Anything for Microscopy model.
        #print(help(get_predictor_and_segmenter))
        points=[]
        n=4
        for i in range(20):
            x = h/2.1 * np.sign(np.cos(i*np.pi/10)) * (abs(np.cos(i*np.pi/10)) ** (2 / n))
            y = w/2.1 * np.sign(np.sin(i*np.pi/10)) * (abs(np.sin(i*np.pi/10)) ** (2 / n))
            points.append(int(h/2+x),int(w/2+y))
        points=np.array([(int(h/2+h/4*np.cos(i*np.pi/10)),int(w/2+w/4*np.sin(i*np.pi/10))) for i in range(20)]+points)
        labels=np.array([1]*20+[0]*20)
        print(list(zip(points,labels)))
        image = (image >> 8).astype(np.uint8)
        image = np.stack([image, image, image], axis=-1)

        predictor, segmenter = get_predictor_and_segmenter(model_type=MODEL_TYPE,is_tiled=False,device="cuda")
        predictor.set_image(image)

        # Now you can use the predictor for masks, points, boxes, etc.
        # If needed, you can get the image embeddings directly:
        image_embeddings = predictor.get_image_embedding()
        print(image_embeddings.shape)
        image_embeddings_dict = {
            "features": image_embeddings,
            "input_size": img.shape,
            "original_size": img.shape,  # original image size or expected input size
        }
        mask=segment_from_points(predictor=predictor,
                                points=points,
                                labels=labels)
        # Run automatic instance segmentation (AIS) on our image.
        #instances = automatic_instance_segmentation(predictor=predictor, segmenter=segmenter, input_path=image)#,tile_shape=(int(h/2+40),int(w/2+40)),halo=(40,40))
        print(type(mask))
        print(mask[0].shape)
        print(mask.dtype)
        print(np.unique(mask[0]))
        mask = mask[0].astype(np.uint8)
        new= largest_component_filled(mask)
        assert not np.all(mask==new)
        new = Image.fromarray(new)
        # Save the image
        Image.fromarray(img).save("/g/schwab/GregoireMichelDeletie/resized.png")
        new.save("/g/schwab/GregoireMichelDeletie/mask_cell.png")
        # Visualize the image and corresponding instance segmentation result.
        print(np.max(mask))