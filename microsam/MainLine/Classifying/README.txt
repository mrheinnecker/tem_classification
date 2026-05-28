aggloclustering - uses the embeddings to classify organelles with agglomerative clustering or other methods. The used embeddings must have been calculated.

knn - uses the embeddings to classify with the knn algorithm. To evalutate the classification and get the confusion matrix, set evaluation to True. To get the accuracy vs K plot, set ktuning to True as well.

getlabels - contains the function to get the labeled dataset. This is based on the image names in labeled_data.


