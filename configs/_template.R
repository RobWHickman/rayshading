# Instructions per map of how to set up and check the mapping pipelines.

# To be copied and filled out per map. Taken as an argument to:
# - `./src/inverse_transform.R configs/map_name.R`
# - `./src/plot_check_points.R configs/map_name.R`

# path to the georeferenced base map
map_path <- "inputs/georeferences/<map_name>.tif"

# (pixel_x, pixel_y, lon, lat) GCPs read off this map. pixel_y matches
# the sign convention used in the gdal_translate -gcp command
# (positive, counted down from the top row) -- NOT the negative values
# QGIS's status bar displays (see README Step 1). Only needed for
# curved/non-straight grids -- see README Step 0.

# when georeferencing can need to inverse_transform, espeically when map uses
# a conical projection. Set the x and y pixel values and the lon/lat
gcps <- data.frame(
  px  = c(),
  py  = c(),
  lon = c(),
  lat = c()
)

# known points that are plotted in `plot_check_points.R` e.g. cities to plot
# on georeferenced map to check
check_points <- list(
  list(name = "", lon = 0, lat = 0)
)
