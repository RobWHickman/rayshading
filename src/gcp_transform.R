# polynomial fit utils for converting between pixel and latlon locations
# when dealing with non-straight grids on maps

design_matrix <- function(lon, lat) {
  cbind(1, lon, lat, lon^2, lon * lat, lat^2)
}

fit_transform <- function(gcps) {
  A <- design_matrix(gcps$lon, gcps$lat)

  coef_x <- qr.solve(A, gcps$px)
  coef_y <- qr.solve(A, gcps$py)

  pred_x <- A %*% coef_x
  pred_y <- A %*% coef_y
  resid <- sqrt((pred_x - gcps$px)^2 + (pred_y - gcps$py)^2)

  for (i in seq_along(resid)) {
    cat(sprintf("GCP %d: residual %.2f px\n", i - 1, resid[i]))
  }

  list(coef_x = coef_x, coef_y = coef_y)
}

lonlat_to_pixel <- function(lon, lat, coef_x, coef_y) {
  A <- design_matrix(lon, lat)
  list(px = as.vector(A %*% coef_x), py = as.vector(A %*% coef_y))
}

# Parse plain-text gdalinfo
raster_info <- function(path) {
  info <- system2("gdalinfo", path, stdout = TRUE)
  origin <- as.numeric(regmatches(
    grep("^Origin", info, value = TRUE),
    gregexpr("-?[0-9.]+", grep("^Origin", info, value = TRUE))
  )[[1]])
  pixel <- as.numeric(regmatches(
    grep("^Pixel Size", info, value = TRUE),
    gregexpr("-?[0-9.]+", grep("^Pixel Size", info, value = TRUE))
  )[[1]])
  size <- as.numeric(regmatches(
    grep("^Size is", info, value = TRUE),
    gregexpr("[0-9]+", grep("^Size is", info, value = TRUE))
  )[[1]])
  list(ulx = origin[1], uly = origin[2], px_w = pixel[1], px_h = pixel[2], w = size[1], h = size[2])
}
