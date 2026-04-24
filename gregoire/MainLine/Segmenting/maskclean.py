# -*- coding: utf-8 -*-
"""
Created on Fri May 16 13:38:14 2025

@author: TEAM
"""
import numpy as np

def clean_masks(masks):
    noises=[remove_borders(masks),mini_masks(masks)]
    for i,row in enumerate(masks):
        for j,mask in enumerate(row):
            noise=sum([noises[k][i][j] for k in range(len(noises))],[])
            mask[np.isin(mask, noise)] = 0
    return masks

def mini_masks(masks):
    noises=[]
    size = 0
    for i,row in enumerate(masks):
        for j,mask in enumerate(row):
            size+=mask.size
    print(size,size/5e4)#roughly 45 for s3
    for i,row in enumerate(masks):
        noises.append([])
        for j,mask in enumerate(row):
            arr_flat = mask.flatten()
            counts = np.bincount(arr_flat)
            noise=[]
            for nb,occ in enumerate(counts):
                if occ<size/5e4:
                    noise.append(nb)
            noises[i].append(noise)
    return noises


def remove_borders(masks):
    noises=[]
    for i,row in enumerate(masks):
        noises.append([])
        for j,mask in enumerate(row):
            noise=set()
            if i==0 :
                noise|=set(mask[:5,:].flatten())
            if j==0 :
                noise|=set(mask[:,:5].flatten())
            if i==len(masks)-1:
                noise|=set(mask[-5:,:].flatten())
            if j==len(row)-1:
                noise|=set(mask[:,-5:].flatten())
            noises[i].append(list(noise))
    return noises



def mismatch(matrix, line_coord, n, pattern_type,depth=3):#line_coord indicates the line/column with zeros to be found
    #return []
    # Define direction offsets for horizontal or vertical
    if pattern_type == "zero_top" or pattern_type == "zero_bottom":
        direct = (0, 1) # horizontal sliding
        line_coord=(line_coord,0)
        l=len(matrix)
    elif pattern_type == "zero_left" or pattern_type == "zero_right":
        direct = (1, 0)  # vertical sliding
        line_coord=(0,line_coord)
        l=len(matrix[0])
        #print(l)
    else:
        raise ValueError(f"Invalid patern: {pattern_type}")
    #print(line_coord)
    if pattern_type == "zero_right":
        line_coord=(line_coord[0],line_coord[1]-depth+1)
        print('offsetted')
    #print(line_coord)
    if pattern_type == "zero_bottom":
        line_coord=(line_coord[0]-depth+1,line_coord[1])
    H, W = matrix.shape
    matches = []
    

    for pos in range(l):
        y0, x0 = line_coord[0]+direct[0]*pos,line_coord[1]+direct[1]*pos

        # Check if the coordinates are in bounds and part of the line
        #print( (n-depth)*direct[0]+depth , (n-depth)*direct[1]+depth)
        if 0 <= y0 < y0+(n-depth)*direct[0]+depth <= H and 0 <= x0 <x0+(n-depth)*direct[1]+depth<= W:
            #print(y0,y0+(n-depth)*direct[0]+depth, x0,x0+(n-depth)*direct[1]+depth)
            #print(y0,y0+(n-2)*direct[0]+2, x0,x0+(n-2)*direct[1]+2)
            values = matrix[y0:y0+(n-depth)*direct[0]+depth, x0:x0+(n-depth)*direct[1]+depth]
            #print(values)
            if pattern_type == "zero_top":
                row1, row2 = values[0], values[-1]
                if np.all(row1 == 0) and np.all(row2 != 0):
                    matches.append(row2.copy())

            elif pattern_type == "zero_bottom":
                row1, row2 = values[0], values[-1]
                if np.all(row1 != 0) and np.all(row2 == 0):
                    matches.append(row1.copy())

            elif pattern_type == "zero_left":
                # Split the values into two parts (first half zeros, second half non-zero)
                left_part = values[:,0]
                right_part = values[:,-1]
                if np.all(left_part == 0) and np.all(right_part != 0):
                    matches.append(right_part.copy())

            elif pattern_type == "zero_right":
                # For "zero_right", first half zeros, second half non-zero
                left_part = values[:,0]
                #print(left_part)
                right_part = values[:,-1]
                if np.all(left_part != 0) and np.all(right_part == 0):
                    matches.append(left_part.copy())

            else:
                raise ValueError(f"Invalid pattern_type: {pattern_type}")
    val=[]
    for match in matches :
        unique_values = np.unique(match)
        if len(unique_values) == 1:
            unique_value = unique_values[0]
            val.append(unique_value)
    return val



class UnionFind:
    def __init__(self):
        self.parent = {}

    def find(self, x):
        # Path compression
        if self.parent.get(x, x) != x:
            self.parent[x] = self.find(self.parent[x])
        return self.parent.get(x, x)

    def union(self, x, y):
        self.parent[self.find(x)] = self.find(y)

def merge_masks(masks,overlap):
    # Initialize
    
    H,W=len(masks)*(len(masks[0][0])-overlap+1),len(masks[0])*(len(masks[0][0][0])-overlap+1)
    h0,w0=masks[0][0].shape
    canvas = np.zeros((H, W), dtype=np.uint16)
    uf = UnionFind()
    label_counter = 1  # global label counter
    #print('Mask :',len(masks))
    for i, row in enumerate(masks):
        for j, tile in enumerate(row):
            h, w = tile.shape
            #print(i, h, overlap)
            y0 = max(0, int(i * (h0 - overlap) - overlap))
            print(y0)
            x0 = max(0, int(j * (w0 - overlap) - overlap))
            y1, x1 = y0 + h, x0 + w
    
            #print(x0,y0)
            # Offset mask labels globally
            mask = tile.astype(np.int16)
            nonzero = mask > 0
            local_ids = np.unique(mask[nonzero])
            #print('local_ids :',len(local_ids) ,'i,j = ',i,j)
            #print('label_counter :',label_counter)
            local_map = {lid: label_counter + idx for idx, lid in enumerate(local_ids)}
            mask[nonzero] = np.vectorize(local_map.get)(mask[nonzero])
            label_counter += len(local_ids)
            
            for direction in ['v','h']:
                # Detect overlaps with existing canvas
                if direction=='v':
                    region = canvas[y0:y1, x0:x0+40]
                    mask_overlap=mask[0:y1-y0, 0:40]
                if direction=='h':
                    region = canvas[y0:y0+40, x0:x1]
                    mask_overlap=mask[0:40, 0:x1-x0]
                buffer = (region > 0) & (mask_overlap > 0)
                printed=set()
                # Union overlapping labels
                for existing, incoming in zip(region[buffer], mask_overlap[buffer]):
                    if existing != incoming:
                        overlap_area = np.sum((region == existing) & (mask_overlap == incoming))
                        if overlap_area>20:
                            uf.union(existing, incoming)
                        if (existing,incoming) not in printed:
                            printed.add((existing,incoming))
            #print("Merged :",[(int(a),int(b)) for a,b in printed])
            # Place the tile
            mask_region = canvas[y0:y1, x0:x1]
            mask_region[mask > 0] = mask[mask > 0]
    
    # Final relabeling pass
    unique, counts = np.unique(canvas, return_counts=True)
    #print('All masks :',len(counts))
    final_canvas = np.zeros_like(canvas,dtype=np.uint16)
    unique_labels = np.unique(canvas[canvas > 0])
    label_map = {old: idx+1 for idx, old in enumerate(sorted({uf.find(lbl) for lbl in unique_labels}))}
    for old_lbl in unique_labels:
        final_canvas[canvas == old_lbl] = label_map[uf.find(old_lbl)]
    #border mismatch
    n=10
    mismatches=[]
    for i in range(len(masks)-1):
        h, w = masks[i][0].shape
        x0 = int((i) * (w0 - 2 * overlap))
        x1 = int((i+1) * (w0 - 2 * overlap))
        mismatches.append(mismatch(final_canvas, line_coord=x0+w, n=n, pattern_type="zero_right"))
        print(x0+w-1,len(mismatches[-1]))
        mismatches.append(mismatch(final_canvas, line_coord=x1-1, n=n, pattern_type="zero_left"))
        print(len(mismatches[-1]))
    for i in range(len(masks[0])-1):
        h, w = masks[0][i].shape
        y0 = int((i) * (h0 - 2 * overlap))
        y1 = int((i+1) * (h0 - 2 * overlap))
        mismatches.append(mismatch(final_canvas, line_coord=y0+h-2, n=n, pattern_type="zero_bottom"))
        print(y0+h-1,len(mismatches[-1]))
        mismatches.append(mismatch(final_canvas, line_coord=y1-1, n=n, pattern_type="zero_top"))
        print(len(mismatches[-1]))
    mismatches=np.unique([e for liste in mismatches for e in liste ])
    print(mismatches)
    unique, counts = np.unique(final_canvas, return_counts=True)
    #print('All masks :',len(counts))
    final_canvas[np.isin(final_canvas, mismatches)] = 0
    #final_canvas[:,w+1] = 498
    #final_canvas[h- 1] = 498
    return final_canvas

if __name__ == '__main__':#for test purposes
        matrix = np.array([
            [0, 5, 3],
            [0, 5, 5],
            [5, 0, 0],
        ])
        result = mismatch(matrix, line_coord=0, n=2, pattern_type="zero_left")
        print(result)