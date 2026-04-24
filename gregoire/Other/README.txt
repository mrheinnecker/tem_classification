celgmentation - segments the cytoplasm of a cell based on point prompts (a center circle is part of it and an outer circle isn't). Worked fine but not extensivelly tested.

cellclusters - make a UMAP and an unsupervised clustering of cells based on the log number of organnelles in each one. Garbage in garbage out.

masksVisu - opens napari and displays a given cell with the segmentation masks for each tile. Can be usefull for visualising micro-sam output and testing maks post-treatement.

teacherStudent - a DINO style finetuning. Will require ajustements before the results are worthwhile.

finetuning - a contrastive loss finetuning. Should work fine on SimCLR but the model isn't as good as DINO.

cutmixFinetuning - a contrastive loss finetuning with cutmix. Due to loss function implementation and overuse of cutmix, the loss doesn't even decrease. Will require major overhall before being usefull (not worthwhile IMO).