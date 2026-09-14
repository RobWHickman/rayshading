# Step 2 of validation - overlay DEM patch on map to get a sense of ovrlap

# Takes a point defined in the configs and expands to a radius of km. Pulls elevation
# data from S3 and overlays it on the map. Warps the DEM data as per the config. Only
# for eyeballing alignment, not a true check

# Usage:
#   Rscript src/hillshade_check_area.R configs/<map_name>.R "City Name" [radius_km] [zoom] [opacity]
source("src/gcp_transform.R")
source("src/hillshade_utils.R")

args <- commandArgs(trailingOnly = TRUE)
config_path <- args[1]
city_name <- args[2]
radius_km <- if (length(args) >= 3) as.numeric(args[3]) else 100
zoom <- if (length(args) >= 4) as.integer(args[4]) else 8
opacity <- if (length(args) >= 5) as.numeric(args[5]) else 55

source(config_path)

city <- Find(function(cp) tolower(cp$name) == tolower(city_name), check_points)
km_per_deg_lat <- 111.32 # Earth circumference / 360
lat1 <- city$lat - radius_km / km_per_deg_lat
lat2 <- city$lat + radius_km / km_per_deg_lat
km_per_deg_lon <- km_per_deg_lat * cos(city$lat * pi / 180)
lon1 <- city$lon - radius_km / km_per_deg_lon
lon2 <- city$lon + radius_km / km_per_deg_lon

xs <- lon2x(lon1, zoom):lon2x(lon2, zoom)
ys <- lat2y(lat2, zoom):lat2y(lat1, zoom)

work_dir <- tempfile("hillshade_area_")
dir.create(work_dir)
tile_tifs <- c()
for (x in xs) {
  for (y in ys) {
    tile_tifs <- c(tile_tifs, fetch_terrarium_tile(x, y, zoom, work_dir))
  }
}
if (length(tile_tifs) == 0) stop("No elevation tiles fetched -- check city coordinates / network.")

mosaic_path <- file.path(work_dir, "mosaic.tif")
system2("gdalwarp", c(tile_tifs, mosaic_path), stdout = FALSE, stderr = FALSE)

fitted <- fit_transform(gcps)
mosaic_info <- raster_info(mosaic_path)

gcp_flags <- c()
for (i in seq_len(nrow(gcps))) {
  dem_px <- (gcps$lon[i] - mosaic_info$ulx) / mosaic_info$px_w
  dem_line <- (gcps$lat[i] - mosaic_info$uly) / mosaic_info$px_h
  dest <- lonlat_to_pixel(gcps$lon[i], gcps$lat[i], fitted$coef_x, fitted$coef_y)
  gcp_flags <- c(gcp_flags, "-gcp", dem_px, dem_line, dest$px, -dest$py)
}
gcp_tif <- file.path(work_dir, "mosaic_gcp.tif")
system2("gdal_translate", c("-a_srs", "EPSG:3857", gcp_flags, mosaic_path, gcp_tif), stdout = FALSE, stderr = FALSE)

dem_on_map_grid <- file.path(work_dir, "dem_on_map_grid.tif")
system2("gdalwarp", c("-order", "2", "-t_srs", "EPSG:3857", "-tr", "1", "1", "-r", "bilinear", "-overwrite", gcp_tif, dem_on_map_grid), stdout = FALSE, stderr = FALSE)

# select only the overlay area
warped_info <- raster_info(dem_on_map_grid)
px0 <- round(warped_info$ulx)
py0 <- round(-warped_info$uly)
px1 <- px0 + warped_info$w
py1 <- py0 + warped_info$h

hillshade_overlay(map_path, dem_on_map_grid, px0, py0, px1, py1, opacity, gsub("[^A-Za-z0-9]+", "-", city$name))

unlink(work_dir, recursive = TRUE)
