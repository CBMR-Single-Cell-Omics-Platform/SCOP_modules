# This pipeline is most useful when a reference snRNAseq dataset is not available and you have some marker genes for your target cell types of interest.

# If you have a good reference snRNAseq dataset, using Seurat anchor transfer might be better.

source('R/find_markers.R')
source('R/sctype_scoring.R')
source('R/annotate_cells.R')
library(future)
library(styler)
library(Matrix)
library(Seurat)
library(tidyverse)

# Load query data
load('data/test.data.B10_ref.based.Rdata') 
# Load reference RNAseq data
hypo.ref <- readRDS('data/ref.cam.hypo.rds') 
# Load markers (an hierarchy marker database), extracted by extracter_marker_hierarcy.R
load('data/marker_db_cam_hypo.Rdata')

# Level 1 annotation ####

# Construct marker gene list:
# Users can also provide their own marker gene list: list(cell_type: markers)
# Select the top n DEGs (target cells vs. background) from each cell type as marker genes. 
# For high level annotation, n within 100 and 200, for low level annotation, n = 30 - 50 should be fine.
top_n = 200
marker_gene_lv1 = contruct_marker_list(marker_db_cam_hypo$lv1, top_n = top_n)

# Example of a marker gene list:
lapply(marker_gene_lv1, head, 5)

# Annotation:
test.data.B10.lv1 = test.data.B10
n_pc = 20

# Define cell clusters,  will be used for cluster level annotation:
test.data.B10.lv1 <- FindNeighbors(test.data.B10.lv1, dims = 1:n_pc, verbose = F)
test.data.B10.lv1 <- FindClusters(test.data.B10.lv1, resolution = 1) 
test.data.B10.lv1 <- cell_annotation_ref_based(test.data.B10.lv1, marker_gene_lv1, label = 'sctype_label.lv1', data_slot = 'scale.data', filter = T)

# Visualization:
# sctype_label.lv1.filtered are cell level annotations (cells with low scores are marked as "Unknown"); 
# sctype_label.lv1.filtered.cluster are cluster level annotations.
DimPlot(test.data.B10.lv1, group.by = c('sctype_label.lv1.filtered','sctype_label.lv1.filtered.cluster'),label = T) & NoLegend()

# Level 2 annotation ####

# We use neuron cells as an example.

# Construct marker gene list (for neuron cell types):

# In contrast to level 1 annotation, we only select top 50 genes (sorted by W score) as marker genes, because the transcriptomics difference among (sub-)cell types might be small at level 2.
top_n = 50
marker_gene_lv2.neuron = contruct_marker_list(marker_db_cam_hypo$lv2$Neuron, top_n = top_n)

# For sub cell-type annotation, we choose 50 PCs and a high resolution for cluster annotation.
n_pc = 50
resolution = 1

# Subset neuron cells scRNAseq data:
neurone_cells = colnames(test.data.B10.lv1)[which(test.data.B10.lv1$sctype_label.lv1.filtered.cluster %in% c('Neuron'))]
test.data.B10.neuron = subset(test.data.B10.lv1, cells = neurone_cells)
test.data.B10.neuron = FindVariableFeatures(test.data.B10.neuron)
test.data.B10.neuron <- FindNeighbors(test.data.B10.neuron, dims = 1:n_pc, verbose = T)
test.data.B10.neuron <- FindClusters(test.data.B10.neuron, resolution = resolution) 
test.data.B10.neuron =  cell_annotation_ref_based(test.data.B10.neuron, marker_gene_lv2.neuron, label = 'sctype_label.lv2')

# Visualization (lvl.2):
# sctype_label.lv2.filtered.cluster are cluster level annotations, depended on cluster annotation (seurat_clusters).
test.data.B10.neuron = RunPCA(test.data.B10.neuron)
test.data.B10.neuron = RunUMAP(test.data.B10.neuron, dims = c(1:n_pc))

DimPlot(test.data.B10.neuron, group.by = c('sctype_label.lv2.filtered.cluster', 'seurat_clusters'),label = T) & NoLegend()

# Compare with Seurat annotation (reference based, a.k.a., anchor transfer) ####

### Level 1 annotation:

# Find anchors:
hypo.ref.anchors <- FindTransferAnchors(reference = hypo.ref, query = test.data.B10.lv1, recompute.residuals = F,
                                        dims = 1:n_pc, reference.reduction = "pca")

# Seurat cell level annotation:
predictions.hypo <- TransferData(anchorset = hypo.ref.anchors, refdata = hypo.ref$taxonomy_lvl2, dims = 1:n_pc)
test.data.B10.lv1 <- AddMetaData(test.data.B10.lv1, metadata = predictions.hypo)

# Seurat cluster level annotation.
test.data.B10.lv1 = cluster_level_annotation(test.data.B10.lv1, sctype_label = 'predicted.id')

# Direct comparison between marker gene based and anchor transfer method:
# Left: Marker gene annotation; Right: Seurat annotation
DimPlot(test.data.B10.lv1, group.by = c('sctype_label.lv1.filtered.cluster','predicted.id.cluster'),label = T) & NoLegend()

### Level 2 annotation:

# Subset neuron cells and find anchors:
hypo.ref.neuron = subset(hypo.ref, subset = `taxonomy_lvl2` == 'Neuron')
hypo.ref.neuron = RunPCA(hypo.ref.neuron)
hypo.ref.neuron = RunUMAP(hypo.ref.neuron, dims = c(1:n_pc))
hypo.ref.neuron.anchors <- FindTransferAnchors(reference = hypo.ref.neuron, query = test.data.B10.neuron, recompute.residuals = F,
                                               dims = 1:n_pc, reference.reduction = "pca")
# Seurat cell level annotation:
predictions.neuron <- TransferData(anchorset = hypo.ref.neuron.anchors, refdata = hypo.ref.neuron$cell_type_all_lvl2, dims = 1:n_pc)
test.data.B10.neuron <- AddMetaData(test.data.B10.neuron, metadata = predictions.neuron)

# Seurat cluster level annotation.
test.data.B10.neuron = cluster_level_annotation(test.data.B10.neuron, sctype_label = 'predicted.id')

# Direct comparison between marker gene based and anchor transfer method:
# Left: Marker gene annotation; Right: Seurat annotation
DimPlot(test.data.B10.neuron, group.by = c('sctype_label.lv2.filtered.cluster', 'predicted.id.cluster'),label = T) & NoLegend()

# Plotting candidate genes:
FeaturePlot(test.data.B10.neuron, features = c('Agrp','Sst','Nfix','Htr2c'))

# **Marker-gene based** and **Reference based (anchor transfer)** give a similar result, the former is dependent on *the quality of marker genes*, whereas the latter is dependent on *the quality of reference snRNAeq data*.