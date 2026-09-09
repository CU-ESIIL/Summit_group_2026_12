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
# can I instead just use the points we already extracted and have R sample the gdp data at those points
# try this here
