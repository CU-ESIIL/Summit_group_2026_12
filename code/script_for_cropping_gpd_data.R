# This script was written to help us crop the real gdp data for each of the cities we downloaded the other data for


# load the necessary libraries
library(terra)
library(sf)
library(geodata)
library(tidyverse)


# subset gdp data to city polygons
## Load city boundaries
city_boundaries <- st_read("C:/Users/User/Downloads/top5_by_continent.geojson")

## Specify the directory path to gdp data files
gdp_dir <- "C:/Users/User/Downloads/Real GDP/"

## Get a list of gdp data files
gdp_files <- dir(gdp_dir, pattern = "*.tif", full.names = TRUE)

# Loop through each climate datafile in climate_files
for (file in gdp_files) {
  # Read climate data
  gdp_raster <- rast(file)
  
  # Crop climate data to city polygons
  cropped_gdp_data <- terra::crop(gdp_raster, city_boundaries)
  
  # Save the cropped climate data
  writeRaster(cropped_gdp_data, paste0("cropped_", basename(file)))
}
