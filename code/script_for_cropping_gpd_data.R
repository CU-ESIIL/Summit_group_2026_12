# This script was written to help us crop the real gdp data for each of the cities we downloaded the other data for


# load the necessary libraries
library(terra)
library(sf)
library(tidyverse)
install.packages("geodata")
library(geodata)

# subset gdp data to city polygons
## Load city boundaries
#city_boundaries <- st_read("C:/Users/User/Downloads/top5_by_continent.geojson")
city_boundaries <- st_read("/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/top5_by_continent.geojson")

## Specify the directory path to gdp data files
gdp_dir <- "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data"

## Get a list of gdp data files
gdp_files <- dir(gdp_dir, pattern = "*.tif", full.names = TRUE)
gdp_files
# Loop through each climate datafile in climate_files
for (file in gdp_files) {
  # Read climate data
  gdp_raster <- rast(file)
  
  # Crop climate data to city polygons
  cropped_gdp_data <- terra::crop(gdp_raster, city_boundaries)
  
  # Save the cropped climate data
  writeRaster(cropped_gdp_data, paste0("cropped_", basename(file)))
}

#check projections
onefile <- rast("/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/cropped_2019GDP.tif")
onefile
#plot(onefile)
ofile <- rast("/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/2019GDP.tif")
ofile
#plot(ofile)
same.crs(onefile, ofile) # good there
# View the spatial extent (xmin, xmax, ymin, ymax) for each raster
ext(onefile)
ext(ofile)
dim(onefile) # this is the problem
dim(ofile)


# did we need the lines above?
# can we instead just use the points we already extracted and have R sample the gdp data at those points
# try this here
# + I think we just want 2019 GDP; at least for now

# ------------------------------------------------------------------------------
# 1. SETUP PATHS AND WORK DIRECTORIES
# ------------------------------------------------------------------------------
clim_dir    <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_worldclim_climate_data"
cluster_dir <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cluster_results"
SES_dir     <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_socio_data/"
output_dir     <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/output_data/"

#GDP_dir     <- "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/"
#file.copy(from = "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/gdp_data/cropped_2019GDP.tif", "~/data-store/home/shared/esiil/Innovation_Summit_2026/Group_12/cropped_socio_data/cropped_2019GDP.tif")

# Load tile metadata and embedding coordinate data
setwd(cluster_dir)
my_map <- read.csv("applied_clusters_knn_10.csv")
colnames(my_map[1:10])
head(my_map[1:5])
tail(my_map[1:5])
dim(my_map)

# Extract the lat,lons
EE_pts <- my_map[, 1:2]
ofile

library(sf)
library(terra)

# 1. Convert your dataframe into an sf object (assuming lat/lon are WGS84 / EPSG:4326)
pts_sf <- st_as_sf(EE_pts, coords = c("lon", "lat"), crs = 4326)

# 2. Project the points to match the raster's CRS (World Mollweide)
pts_p <- st_transform(pts_sf, crs = crs(ofile))

# 3. Extract the raster values for these points
### TODO Fix ERROR. I get an error here that I don't know how to fix
extracted_vals <- terra::extract(ofile, pts_p)

# 4. Combine the extracted values back with your original data
EE_pts_with_gdp <- cbind(EE_pts, extracted_vals)

head(EE_pts_with_gdp)

                 