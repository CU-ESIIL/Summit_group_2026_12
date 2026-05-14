# Description:This script was written to help us download climate data for our selected cities.
# Date: 5/14/2026


# load the necessary libraries
library(terra)
library(geodata)
library(tidyverse)


# get global climate data 
geodata::worldclim_global(
  country = NULL,
  var = "bio",
  res = 0.008333,
  version = "2.1",
  path = "/data-store/iplant/home/shared/esiil/Innovation_Summit_2026/Group_12/"
)