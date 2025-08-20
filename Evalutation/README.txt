Classfolder - Creates folders and fills them with copies of images based on their assigned class. Can help visually evaluating cluster consistency.

Clusterestimation - helps estimating the number of clusters that should be used with the unsupervised classification by plotting cluster number against distance to next merge.

EvalClassAgglo - aligns the namless clusters to the database's labels and calculates a confusion matrix as well as accuracy and other metrics.

EvalClassMasks - calculates the pixelwise accuracy and recall of organelle specific masks and plots their repartition.

To evaluate the knn classification, see knn.py in the mainline ast this classifier has a built-in evaluation and K estimator by setting evaluation and ktuning to True respectivelly.