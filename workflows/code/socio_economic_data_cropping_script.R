# Description: This file was written to help us crop our socio-economic data to our city boundaries.


# load in socio-economic data
city_boundaries <- st_read("/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/top5_by_continent (1).geojson")

# Specify the directory path to socio-econ data files
socioecon_dat <- "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/socio/landscan-global-2019.tif"

# Read climate data
socioecon_dat_raster <- rast(socioecon_dat)

# crop socio-econ data to city boundaries
cropped_socio_data <- terra::crop(socioecon_dat_raster, city_boundaries)


# Save the cropped socio-econ data
writeRaster(cropped_socio_data, paste0("cropped_", basename(socioecon_dat)))
