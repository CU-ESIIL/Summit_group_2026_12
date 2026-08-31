# ==============================================================================
# GLOBAL URBAN TYPOLOGIES: END-TO-END ORDINATION PIPELINE
# ==============================================================================
install.packages("vegan")
library(sf)
library(vegan)
library(terra)
library(dplyr)
library(ggplot2)

# ------------------------------------------------------------------------------
# 1. SETUP PATHS AND WORK DIRECTORIES
# ------------------------------------------------------------------------------
clim_dir    <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_worldclim_climate_data"
cluster_dir <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cluster_results"
SES_dir     <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_socio_data/"
#GDP_dir     <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/"
#file.copy(from = "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/cropped_2019GDP.tif", "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_socio_data/cropped_2019GDP.tif")

# Load tile metadata and embedding coordinate data
setwd(cluster_dir)
my_map <- read.csv("applied_clusters_knn_10.csv")

# Extract the 4,000 embedding features
feature_cols <- 6:4005
X <- my_map[, feature_cols]

# ------------------------------------------------------------------------------
# 2. FEATURE L2-NORMALIZATION (Cosine Adjustment)
# ------------------------------------------------------------------------------
l2_normalize <- function(M) {
  denom <- sqrt(rowSums(M^2))
  M / pmax(denom, 1e-12)
}
#X_norm <- l2_normalize(X)

# ------------------------------------------------------------------------------
# 3. SPATIAL SETUP: CONVERT TILE COORDINATES TO AN SF GEOMETRY OBJECT
# ------------------------------------------------------------------------------
tiles_df <- my_map[, c("lon", "lat", "shapeGroup", "adm2_shapeID_geoBoundaries", "adm1_shapeID_geoBoundaries")]
tiles_sf <- st_as_sf(tiles_df, coords = c("lon", "lat"), crs = 4326, remove = FALSE)

# ------------------------------------------------------------------------------
# 4. STEPWISE ENVIRONMENTAL EXTRACTION (Nearest Neighbor / Simple)
# ------------------------------------------------------------------------------

# --- Climate Data ---
setwd(clim_dir)
raster_files <- list.files(clim_dir, pattern = "\\.tif$")
raster_stack <- rast(raster_files)
r_crs        <- terra::crs(raster_stack)

if (st_crs(tiles_sf)$wkt != r_crs) {
  tiles_sf_clim <- st_transform(tiles_sf, st_crs(r_crs))
} else {
  tiles_sf_clim <- tiles_sf
}

clim_vals <- terra::extract(raster_stack, terra::vect(tiles_sf_clim), method = "simple")
tiles_clim_data <- bind_cols(tiles_sf_clim, select(clim_vals, -ID))

# --- Socio-Economic (SES) Data ---
setwd(SES_dir)
# TODO remove the 2019 once Isaac sends me the GDP with the correct extent
ses_files <- list.files(SES_dir, pattern = "2019\\.tif$", full.names = TRUE)
ses_stack <- terra::rast(ses_files)
ses_crs   <- terra::crs(ses_stack)
# Print out the extents of all files to spot the culprit
lapply(ses_files, function(x) terra::ext(terra::rast(x)))
if (st_crs(tiles_clim_data)$wkt != ses_crs) {
  tiles_vect_ses <- terra::vect(st_transform(tiles_clim_data, st_crs(ses_crs)))
} else {
  tiles_vect_ses <- terra::vect(tiles_clim_data)
}

ses_vals        <- terra::extract(ses_stack, tiles_vect_ses, method = "simple")
tiles_env_final <- bind_cols(tiles_clim_data, select(ses_vals, -ID))

# ------------------------------------------------------------------------------
# 5. REMOVE NA VALUES & REALIGN EMBEDDING MATRIX
# ------------------------------------------------------------------------------
# Ensure rows with missing raster coverage (coastal edges) are dropped symmetrically
tiles_clean <- tiles_env_final %>% 
  filter(if_all(6:25, ~ !is.na(.)))

clean_row_indices <- as.numeric(rownames(tiles_clean))
embeddings_subset <- X[clean_row_indices, ] # or use L2-normalized embeddings here

# ------------------------------------------------------------------------------
# 6. SPATIAL JOIN: APPEND CITY AND CONTINENT NAME LABELS TO TILES
# ------------------------------------------------------------------------------
cities <- read_sf("~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/city_displays.geojson")

if (st_crs(tiles_clean) != st_crs(cities)) {
  cities <- st_transform(cities, st_crs(tiles_clean))
}

# Run spatial intersection join
# is cities a point file?? if polygon run:
#tiles_with_labels <- st_join(tiles_clean, cities, join = st_intersects)
tiles_with_labels <- st_join(tiles_clean, cities, join = st_nearest_feature)

# Extract and attach explicit structural descriptors
# (Verify that 'display_name' and 'continent' match your geojson file's colnames exactly)
tiles_clean$City_Label      <- tiles_with_labels$display_name
tiles_clean$Continent_Label <- tiles_with_labels$Continent

# ------------------------------------------------------------------------------
# 7. SCALE-CENTRIC LINEAR ORDINATION & VECTOR ANALYSIS (PCA + envfit)
# ------------------------------------------------------------------------------
# scale = TRUE centers columns to mean 0 and standardizes variance to unit scale
pca_model <- rda(embeddings_subset, scale = TRUE)

# Strip spatial geometry completely before fitting environmental vectors
env_slice   <- st_drop_geometry(tiles_clean[, 6:25])
fit_vectors <- envfit(pca_model, env_slice, permutations = 999)

# ------------------------------------------------------------------------------
# 8. EXTRACT SITES & VECTOR COALS FOR PLOTTING
# ------------------------------------------------------------------------------
tile_scores           <- as.data.frame(scores(pca_model, choices = c(1, 2), display = "sites"))
tile_scores$City      <- tiles_clean$City_Label
tile_scores$Continent <- tiles_clean$Continent_Label

vector_scores           <- as.data.frame(scores(fit_vectors, display = "vectors"))
vector_scores$Variable  <- rownames(vector_scores)

# Scaling factor to expand length of envfit vector lines inside the ordination window
arrow_scaler             <- 2  
vector_scores$PC1_scaled <- vector_scores$PC1 * arrow_scaler
vector_scores$PC2_scaled <- vector_scores$PC2 * arrow_scaler

# 1. Check how many NAs are causing the drop
sum(is.na(tile_scores$City))
sum(is.na(tile_scores$Continent))

# 2. Convert NAs to explicit categories so ggplot keeps them
tile_scores$City[is.na(tile_scores$City)]           <- "Unknown/Coastal Edge"
tile_scores$Continent[is.na(tile_scores$Continent)]  <- "Other/Marine"

# 3. Ensure they are treated as factors
tile_scores$City      <- as.factor(tile_scores$City)
tile_scores$Continent <- as.factor(tile_scores$Continent)

# 4. Count the distinct number of continents to make sure our shape vector matches
num_continents <- length(levels(tile_scores$Continent))
print(num_continents)

# ------------------------------------------------------------------------------
# 9. VARIANCE ANALYSIS & SCREE PLOT
# ------------------------------------------------------------------------------

# Get the summary of the PCA
pca_summary <- summary(pca_model)

# Extract the proportion of variance explained by each PC
# 'cont' contains the Importance of components table
importance_table <- pca_summary$cont$importance

# Print the first 10 PCs (usually where most variance lives)
print(importance_table[, 1:10])

# Extract eigenvalues from the PCA model
eigenvalues <- eigenvals(pca_model)

# Calculate proportion of variance explained
prop_var <- eigenvalues / sum(eigenvalues)
cumul_var <- cumsum(prop_var)

# How many PCs to display (first 30 is usually enough)
n_display <- 10
# Create a Scree Plot to visualize the "elbow"
# This helps justify how many PCs you chose to keep
# Build a dataframe for ggplot
scree_df <- data.frame(
  PC         = 1:n_display,
  PropVar    = as.numeric(prop_var[1:n_display]),
  CumulVar   = as.numeric(cumul_var[1:n_display])
)

# Scree plot with cumulative variance overlay
ggplot(scree_df, aes(x = PC)) +
  geom_col(aes(y = PropVar), fill = "steelblue", alpha = 0.7) +
  geom_line(aes(y = CumulVar), color = "firebrick", linewidth = 1) +
  geom_point(aes(y = CumulVar), color = "firebrick", size = 2) +
  geom_hline(yintercept = 0.80, linetype = "dashed", color = "grey40") +
  annotate("text", x = n_display * 0.7, y = 0.82,
           label = "80% variance threshold", color = "grey40", size = 3) +
  scale_y_continuous(
    name     = "Proportion of Variance Explained",
    sec.axis = sec_axis(~., name = "Cumulative Variance")
  ) +
  labs(x     = "Principal Component",
       title = "Scree Plot — MOSAIKS Earth Embeddings") +
  theme_minimal()

# Clean summary table for the first 20 PCs
variance_table <- data.frame(
  PC             = paste0("PC", 1:20),
  Eigenvalue     = as.numeric(eigenvalues[1:20]),
  Prop_Variance  = round(as.numeric(prop_var[1:20]), 4),
  Cumul_Variance = round(as.numeric(cumul_var[1:20]), 4)
)

print(variance_table)

# First two PCs or first four?
#TODO before running PCA (ahem) check linear relation between EEs 
#how to handle that for 4000 features?

# ------------------------------------------------------------------------------
# 9. ADVANCED GEOM RELEVANT GGPLOT GENERATION
# ------------------------------------------------------------------------------
ggplot() +
  # 1. Draw points using City colors and Continent shapes
  geom_point(data = tile_scores, aes(x = PC1, y = PC2, color = City, shape = Continent), 
             alpha = 0.3, size = 0.8) +
  
  # 2. Superimpose maximum directional correlation vectors
  geom_segment(data = vector_scores, 
               aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.2, "cm")), 
               color = "black", linewidth = 0.8) +
  
  # 3. Dynamically append vector labels
  geom_text(data = vector_scores, 
            aes(x = PC1_scaled * 1.1, y = PC2_scaled * 1.1, label = Variable),
            fontface = "bold", size = 3.5) +
  
  # Overrides shape limits to ensure all continents map cleanly to a point geometry
  scale_shape_manual(values = c(16, 17, 15, 18, 3, 4, 8)) + 
  
  theme_minimal() +
  labs(title = "Global Earth Embedding Typologies Across 30 Cities",
       subtitle = "Spatial Coordination of City Morphology, Regional Geographies, and Local Drivers",
       x = "PCA Axis 1", y = "PCA Axis 2",
       color = "City Locations", shape = "Continental Regions") +
  theme(legend.position = "right",
        plot.title = element_text(face = "bold", size = 14),
        axis.title = element_text(face = "bold"))

ggplot() +
  # Replace geom_point with density rings colored by City
  geom_density_2d(data = tile_scores, aes(x = PC1, y = PC2, color = City), 
                  linewidth = 0.5, alpha = 0.8) +
  
  # Keep your environmental vectors exactly as they were
  geom_segment(data = vector_scores, 
               aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.2, "cm")), color = "black", linewidth = 0.8) +
  geom_text(data = vector_scores, aes(x = PC1_scaled * 1.1, y = PC2_scaled * 1.1, label = Variable),
            fontface = "bold", size = 3.5) +
  theme_minimal()


ggplot(tile_scores, aes(x = PC1, y = PC2)) +
  # Drop shapes entirely; just color points by city
  geom_point(aes(color = City), alpha = 0.1, size = 0.4) +
  
  # Environmental vectors will print identically onto every facet panel
  geom_segment(data = vector_scores, aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.2, "cm")), color = "red", linewidth = 0.6) +
  
  # Split into a clean grid of mini-plots based on Continent
  facet_wrap(~Continent, ncol = 3) +
  
  theme_minimal() +
  theme(legend.position = "bottom") # Puts the large legend underneath the layout


# 1. Calculate the convex hull boundary points for every city group
city_hulls <- tile_scores %>%
  group_by(City) %>%
  slice(chull(PC1, PC2))

# 2. Calculate the central point (mean) for each city to place text labels
city_centroids <- tile_scores %>%
  group_by(City) %>%
  summarize(PC1 = mean(PC1), PC2 = mean(PC2))

# 3. Plot the clean hulls instead of points
ggplot() +
  # Draw shaded boundary rings for each city
  geom_polygon(data = city_hulls, aes(x = PC1, y = PC2, fill = City, color = City), 
               alpha = 0.15, linewidth = 0.5) +
  
  # Drop the legend and place explicit text labels right on the city clusters
  geom_text(data = city_centroids, aes(x = PC1, y = PC2, label = City, color = City), 
            size = 3, fontface = "bold", check_overlap = TRUE) +
  
  # Superimpose vectors
  geom_segment(data = vector_scores, aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.2, "cm")), color = "black", linewidth = 0.8) +
  geom_text(data = vector_scores, aes(x = PC1_scaled * 1.1, y = PC2_scaled * 1.1, label = Variable),
            fontface = "bold", size = 4) +
  
  theme_minimal() +
  theme(legend.position = "none") # Hides the messy 30-color legend block


# ==============================================================================
# 1. CALCULATE GEOMETRIC COMPONENT STRUCTURES FOR THE PLOT
# ==============================================================================

# Step A: Calculate the convex hull boundaries grouping by BOTH City and Continent
city_hulls_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  slice(chull(PC1, PC2)) %>%
  ungroup()

# Step B: Calculate the spatial centroid of each city for direct text labeling
city_centroids_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  summarize(PC1 = mean(PC1), PC2 = mean(PC2), .groups = "drop")


# ==============================================================================
# 2. GENERATE THE FACETED CONVEX HULL MAP
# ==============================================================================

ggplot() +
  # 1. Draw the shaded convex hulls for each city group
  geom_polygon(data = city_hulls_faceted, 
               aes(x = PC1, y = PC2, fill = City, color = City), 
               alpha = 0.15, linewidth = 0.6) +
  
  # 2. Add explicit text labels at the center of each city's hull footprint
  # 'check_overlap = TRUE' prevents labels from stacking illegibly if clusters merge
  geom_text(data = city_centroids_faceted, 
            aes(x = PC1, y = PC2, label = City, color = City), 
            size = 2.8, fontface = "bold", check_overlap = TRUE, vjust = -0.5) +
  
  # 3. Superimpose the environmental & socio-economic vectors onto every panel
  geom_segment(data = vector_scores, 
               aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.15, "cm")), 
               color = "grey20", linewidth = 0.7) +
  
  # 4. Dynamically append structural labels to the vectors
  geom_text(data = vector_scores, 
            aes(x = PC1_scaled * 1.15, y = PC2_scaled * 1.15, label = Variable),
            fontface = "bold", size = 3, color = "black") +
  
  # 5. Execute the split across Continental Regions
  # Adjust 'ncol' based on display proportions (e.g., 3 columns or 4 columns)
  facet_wrap(~Continent, ncol = 3) +
  
  # ----------------------------------------------------------------------------
# STYLING AND PRESENTATION OVERRIDES
# ----------------------------------------------------------------------------
theme_minimal() +
  labs(
    title = "Global Earth Embedding Typologies by Continental Region",
    subtitle = "Macro-Scale Footprints of 30 Cities Relative to Local Environmental and Socio-Economic Drivers",
    x = "Principal Component Axis 1", 
    y = "Principal Component Axis 2"
  ) +
  theme(
    legend.position = "none", # Direct text labels remove the need for a 30-color legend
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 5)),
    plot.subtitle = element_text(color = "grey30", size = 10, margin = margin(b = 15)),
    strip.background = element_rect(fill = "grey95", color = "transparent"), # Prominent facet headers
    strip.text = element_text(face = "bold", size = 11, color = "grey10"),
    axis.title = element_text(face = "bold", size = 10),
    panel.spacing = unit(1.5, "lines"), # Adds breathing room between charts
    panel.grid.minor = element_blank()  # Cleans up background noise
  )



# ==============================================================================
# 1. SETUP GROUP-LEVEL METADATA & PANEL-SPECIFIC LINETYPES
# ==============================================================================

# Calculate hulls and inject an inside-panel index for unique linetypes
city_hulls_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  slice(chull(PC1, PC2)) %>%
  ungroup() %>%
  # Assign a number (1, 2, 3...) to each city *within* its own continent panel
  group_by(Continent) %>%
  mutate(City_Panel_Index = as.numeric(as.factor(City))) %>%
  ungroup() %>%
  # Map that index to 4 highly distinct line styles (solid, dashed, dotted, dotdash)
  mutate(Line_Style = case_when(
    City_Panel_Index %% 4 == 1 ~ "solid",
    City_Panel_Index %% 4 == 2 ~ "dashed",
    City_Panel_Index %% 4 == 3 ~ "dotted",
    TRUE                       ~ "dotdash"
  ))

# Calculate centroids for label placement
city_centroids_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  summarize(PC1 = mean(PC1), PC2 = mean(PC2), .groups = "drop")


# ==============================================================================
# 2. GENERATE LAYER-ORDERED GGPLOT
# ==============================================================================

ggplot() +
  
  # LAYER 1 [BOTTOM]: Shaded Convex Hulls with Multi-Style Dashed Outlines
  geom_polygon(data = city_hulls_faceted, 
               aes(x = PC1, y = PC2, fill = City, color = City, linetype = Line_Style), 
               alpha = 0.12, linewidth = 0.7) +
  
  # LAYER 2 [MIDDLE]: Environmental and Socio-Economic Vector Arrows
  geom_segment(data = vector_scores, 
               aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.15, "cm")), 
               color = "grey10", linewidth = 0.8) +
  
  # # LAYER 3 [MIDDLE]: Labels for Vector Arrows
  # geom_text(data = vector_scores, 
  #           aes(x = PC1_scaled * 1.15, y = PC2_scaled * 1.15, label = Variable),
  #           fontface = "bold", size = 3.2, color = "black") +
  
  # LAYER 4 [TOP]: Bold City Name Labels (Rendered last so they stay on top)
  geom_text(data = city_centroids_faceted, 
            aes(x = PC1, y = PC2, label = City, color = City), 
            size = 3.2, fontface = "bold", check_overlap = FALSE) +
  
  # ----------------------------------------------------------------------------
# SCALES, FACETING, AND THEME OVERRIDES
# ----------------------------------------------------------------------------

# Direct identity link to interpret the linetype strings properly
scale_linetype_identity() + 
  
  facet_wrap(~Continent, ncol = 3) +
  theme_minimal() +
  
  labs(
    title = "Global Earth Embedding Typologies by Continental Region",
    subtitle = "Dashed boundaries represent morphological footprint variance; labels prioritized on top layer",
    x = "Principal Component Axis 1", 
    y = "Principal Component Axis 2"
  ) +
  
  theme(
    legend.position = "none", # Direct labeling handles city identification
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 5)),
    plot.subtitle = element_text(color = "grey30", size = 10, margin = margin(b = 15)),
    strip.background = element_rect(fill = "grey95", color = "transparent"),
    strip.text = element_text(face = "bold", size = 11, color = "grey10"),
    axis.title = element_text(face = "bold", size = 10),
    panel.spacing = unit(1.8, "lines"),
    panel.grid.minor = element_blank()
  )

############# Bringing in the clusters

# ==============================================================================
# 1. PREPARE THE DATA & MERGE KNN CLUSTERS
# ==============================================================================

# Option B: If you need to match them strictly by their spatial coordinates
tile_scores <- tile_scores %>%
  left_join(dplyr::select(my_map, Lon, Lat, cluster_knn), by = c("Lon", "Lat")) %>%
  mutate(cluster_knn = as.factor(cluster_knn))

# Recalculate hulls with the updated dataframe structure
city_hulls_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  slice(chull(PC1, PC2)) %>%
  ungroup() %>%
  group_by(Continent) %>%
  mutate(City_Panel_Index = as.numeric(as.factor(City))) %>%
  ungroup() %>%
  mutate(Line_Style = case_when(
    City_Panel_Index %% 4 == 1 ~ "solid",
    City_Panel_Index %% 4 == 2 ~ "dashed",
    City_Panel_Index %% 4 == 3 ~ "dotted",
    TRUE                       ~ "dotdash"
  ))

# Recalculate centroids
city_centroids_faceted <- tile_scores %>%
  group_by(Continent, City) %>%
  summarize(PC1 = mean(PC1), PC2 = mean(PC2), .groups = "drop")


# ==============================================================================
# 2. GENERATE THE LAYERED PLOT WITH RAW CLUSTER POINTS
# ==============================================================================

ggplot() +
  
  # LAYER 1: Shaded Convex Hulls with Multi-Style Dashed Outlines
  geom_polygon(data = city_hulls_faceted, 
               aes(x = PC1, y = PC2, fill = City, color = City, linetype = Line_Style), 
               alpha = 0.08, linewidth = 0.6) +
  
  # LAYER 2: The Raw Points, Shaped by KNN Cluster and Colored by City
  # Alpha is set low (0.15) so 84,000 points don't form a solid block
  geom_point(data = tile_scores, 
             aes(x = PC1, y = PC2, color = City, shape = cluster_knn), 
             alpha = 0.15, size = 0.5) +
  
  # LAYER 3: Environmental and Socio-Economic Vector Arrows
  geom_segment(data = vector_scores, 
               aes(x = 0, y = 0, xend = PC1_scaled, yend = PC2_scaled),
               arrow = arrow(length = unit(0.12, "cm")), 
               color = "grey10", linewidth = 0.8) +
  
  # LAYER 4: Labels for Vector Arrows
  geom_text(data = vector_scores, 
            aes(x = PC1_scaled * 1.15, y = PC2_scaled * 1.15, label = Variable),
            fontface = "bold", size = 3.2, color = "black") +
  
  # LAYER 5 [TOP]: Bold City Name Labels (Guaranteed on top of points/lines)
  geom_text(data = city_centroids_faceted, 
            aes(x = PC1, y = PC2, label = City, color = City), 
            size = 3.5, fontface = "bold") +
  
  # ----------------------------------------------------------------------------
# SCALES, FACETING, AND THEME OVERRIDES
# ----------------------------------------------------------------------------

# Identity link for the custom dashed line strings
scale_linetype_identity() + 
  
  # Explicitly map 10 highly distinct, legible point symbols for the clusters
  # 16-18 are filled shapes, 0-4 are open shapes, 8 is a star, etc.
  scale_shape_manual(values = c(16, 17, 15, 18, 0, 1, 2, 5, 6, 8)) +
  
  facet_wrap(~Continent, ncol = 3) +
  theme_minimal() +
  
  labs(
    title = "Global Earth Embedding Typologies by Continental Region",
    subtitle = "Points shaped by k-NN Cluster (1-10); Envelopes show overall city morphological footprint",
    x = "Principal Component Axis 1", 
    y = "Principal Component Axis 2",
    shape = "k-NN Cluster ID"
  ) +
  
  theme(
    legend.position = "right",         # Show ONLY the cluster shape legend
    legend.title = element_text(face = "bold", size = 10),
    guides = list(color = "none", fill = "none"), # Hide the massive 30-color city legends
    plot.title = element_text(face = "bold", size = 14, margin = margin(b = 5)),
    plot.subtitle = element_text(color = "grey30", size = 10, margin = margin(b = 15)),
    strip.background = element_rect(fill = "grey95", color = "transparent"),
    strip.text = element_text(face = "bold", size = 11, color = "grey10"),
    axis.title = element_text(face = "bold", size = 10),
    panel.spacing = unit(1.8, "lines"),
    panel.grid.minor = element_blank()
  )

# ------------------------------------------------------------------------------
# 20. PERMANOVA — BETWEEN vs. WITHIN CITY VARIANCE
# ------------------------------------------------------------------------------
#library(vegan)

# --- Option A: On raw embeddings (RECOMMENDED for paper) ---
#dist_raw <- vegdist(embeddings_subset, method = "bray")

# --- Option B: On first 4 PCs only ---
pc_scores_4 <- as.data.frame(scores(pca_model, 
                                     choices = 1:4, 
                                     display = "sites"))
# 
#dist_pca <- vegdist(pc_scores_4, method = "euclidean")  
# Note: Euclidean is appropriate for PCA scores since they are already 
# orthogonal and standardized

# Just extract City names as a clean vector — same row order as embeddings_subset
city_vector <- tile_scores$City

# Sanity check — this MUST be TRUE before running PERMANOVA
stopifnot(nrow(embeddings_subset) == length(city_vector))

# Also useful to have continent for a secondary PERMANOVA
continent_vector <- tile_scores$Continent

# --- Primary PERMANOVA: City as grouping factor ---
set.seed(42)  # For reproducibility — important for a paper
# Let adonis2 compute distances internally — much more memory efficient
permanova_city <- adonis2(
  pc_scores_4 ~ city_vector,   # pass the DATA FRAME, not the dist object
  method       = "euclidean",  # appropriate for PCA scores
  permutations = 999,
  by           = "margin"      # tests each term after all others — more conservative
)

print(permanova_city)

# --- Secondary PERMANOVA: Continent as grouping factor ---


print(permanova_continent)

# --- Nested PERMANOVA: City nested within Continent ---
# This is the most informative for your RQ2
permanova_nested <- adonis2(
  dist_pca ~ continent_vector / city_vector,
  permutations = 999
)

print(permanova_nested)
