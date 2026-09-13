# Inverse transform: lon/lat -> historical map pixel coordinates.

# Allows resampling of WGS84 DEM onto original natice pixel grid. Useful when
# map uses a conical graticule, i.e. not straigt horizontal lines. Fits QGIS'
# 2nd degree polynomial in reverse

# Set pixel/lat lon coordinates in `./configs/<map_name>.R` and pass as a
# command line argument (or get the LLM to do it)

source("src/gcp_transform.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) stop("Usage: Rscript src/inverse_transform.R configs/<map_name>.R")
source(args[1]) # brings in map_path, gcps, check_points

fitted <- fit_transform(gcps)
coef_x <- fitted$coef_x
coef_y <- fitted$coef_y

cat("\ncoef_x:\n")
print(coef_x)
cat("\ncoef_y:\n")
print(coef_y)

# quick check: should give a sane in-range pixel location for each
# known check point, confirmable by eye against the raster (or see
# plot_check_points.R for the visual version of this check)
for (cp in check_points) {
  result <- lonlat_to_pixel(cp$lon, cp$lat, coef_x, coef_y)
  cat(sprintf(
    "\n%s (%.2fE, %.2fN) -> pixel (%.1f, %.1f)\n",
    cp$name, cp$lon, cp$lat, result$px, result$py
  ))
}
