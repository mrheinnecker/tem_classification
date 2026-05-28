# -*- coding: utf-8 -*-
"""
Created on Mon Jul 14 10:16:38 2025

@author: TEAM
"""
import os
for y in os.listdir(r"/g/schwab/GregoireMichelDeletie/slurm_outputs"):
    if y.startswith("cell_nb"):
        for x in os.listdir(os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext")):
            if x.endswith(".png") and "c" not in x:
                origin = os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",x)
                cell_nb=y[len("cell_nb_"):] 
                org_nb=x[len("organelle_"):-len(".png")] 
                destination=os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",f"c{cell_nb}o{org_nb}.png")
                os.rename(origin, destination)
            if "." not in x:
                origin = os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",x)
                destination=os.path.join(r"/g/schwab/GregoireMichelDeletie/slurm_outputs",y,"maskstoreContext",x+".png")
                os.rename(origin, destination)
        