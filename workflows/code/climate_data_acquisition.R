# Description:This script was written to help us download and crop climate data for our selected cities.


# load the necessary libraries
library(terra)
library(sf)
library(geodata)
library(tidyverse)


# get global climate data 
geodata::worldclim_global(
  country = NULL,
  var = "bio",
  res = 0.5,
  version = "2.1",
  path = "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/worldclim_climate_data/"
)


# subset climate data to city polygons
# Load city boundaries
city_boundaries <- st_read("/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/top5_by_continent.geojson")

# Specify the directory path to climate data files
climate_dir <- "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/worldclim_climate_data/"

# Get a list of climate data files
climate_files <- dir(climate_dir, pattern = "*.tif", full.names = TRUE)

# Loop through each climate datafile in climate_files
for (file in climate_files) {
  # Read climate data
  climate_raster <- rast(file)
  
  # Crop climate data to city polygons
  cropped_climate_data <- terra::crop(climate_raster, city_boundaries)
  
  # Save the cropped climate data
  writeRaster(cropped_climate_data, paste0("cropped_", basename(file)))
}
