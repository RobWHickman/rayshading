# Helpers for DEM tile fetching and hillshade-vs-map overlay checks.
library(magick)

# convert map tile to lon/lat
lon2x <- function(lon, z) floor((lon + 180) / 360 * 2^z)
lat2y <- function(lat, z) {
  r <- lat * pi / 180
  floor((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * 2^z)
}
x2lon <- function(x, z) x / 2^z * 360 - 180
y2lat <- function(y, z) {
  n <- pi - 2 * pi * y / 2^z
  180 / pi * atan(sinh(n))
}

# fetch and save a terrarium map tile file from s3
fetch_terrarium_tile <- function(x, y, zoom, work_dir) {
  png_path <- file.path(work_dir, sprintf("%d_%d.png", x, y))
  url <- sprintf("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png", zoom, x, y)
  status <- system2("curl", c("-sL", "-f", url, "-o", png_path))
  if (status != 0) return(NULL)

  img <- image_data(image_read(png_path), channels = "rgb")
  r <- matrix(as.integer(img[1, , ]), nrow = dim(img)[2])
  g <- matrix(as.integer(img[2, , ]), nrow = dim(img)[2])
  b <- matrix(as.integer(img[3, , ]), nrow = dim(img)[2])
  elev <- r * 256 + g + b / 256 - 32768

  raw_path <- file.path(work_dir, sprintf("%d_%d.bin", x, y))
  writeBin(as.vector(elev), raw_path, size = 4)
  writeLines(c(
    "ENVI", sprintf("samples = %d", nrow(elev)), sprintf("lines = %d", ncol(elev)),
    "bands = 1", "header offset = 0", "file type = ENVI Standard",
    "data type = 4", "interleave = bsq", "byte order = 0"
  ), sub("\\.bin$", ".hdr", raw_path))

  tif_path <- file.path(work_dir, sprintf("%d_%d.tif", x, y))
  system2("gdal_translate", c(
    "-of", "GTiff", "-a_srs", "EPSG:4326",
    "-a_ullr", x2lon(x, zoom), y2lat(y, zoom), x2lon(x + 1, zoom), y2lat(y + 1, zoom),
    raw_path, tif_path
  ), stdout = FALSE, stderr = FALSE)
  tif_path
}

# see hillshade_check_area.R
hillshade_overlay <- function(map_path, dem_path, px0, py0, px1, py1, opacity = 50, suffix = "") {
  hillshade_tif <- tempfile(fileext = ".tif")
  status <- system2("gdaldem", c("hillshade", dem_path, hillshade_tif))
  if (status != 0) stop("gdaldem hillshade failed -- is GDAL installed and on PATH?")

  w <- px1 - px0
  h <- py1 - py0
  map_crop <- image_crop(image_read(map_path), geometry_area(w, h, px0, py0))
  hillshade_img <- image_resize(image_read(hillshade_tif), paste0(w, "x", h, "!"))
  blended <- image_composite(map_crop, hillshade_img, operator = "blend", compose_args = as.character(opacity))

  dir.create("outputs/checks", recursive = TRUE, showWarnings = FALSE)
  if (nzchar(suffix)) suffix <- paste0("_", suffix)
  out_path <- file.path("outputs/checks", paste0(tools::file_path_sans_ext(basename(map_path)), "_hillshade_check", suffix, ".png"))
  image_write(blended, out_path, format = "png")
  cat(sprintf("\nWrote %s -- confirm hillshade ridgelines align with the map's drawn relief.\n", out_path))
  out_path
}
