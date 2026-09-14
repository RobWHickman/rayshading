# Step 1 of validation - plot known points over georeferenced map

# Known points (e.g. cities) are defined in `./configs/<map_name>.R` and
# passed into here as command line arguments. These are plotted over the
# downsampled georeferenced map as star with the name of the location.
# Output is saved to `./outputs/checks`

# Usage:
#   Rscript src/plot_check_points.R configs/<map_name>.R [plot_scale]
library(magick)
source("src/gcp_transform.R")

args <- commandArgs(trailingOnly = TRUE)
config_path <- args[1]
source(config_path)

# Downscale the map .tif for plotting quickly if passed
# otherwise keep at full resolution (default = 1)
plot_scale <- if (length(args) >= 2) as.numeric(args[2]) else 1

fitted <- fit_transform(gcps)
coef_x <- fitted$coef_x
coef_y <- fitted$coef_y

img <- image_read(map_path)
if (plot_scale != 1) {
  img <- image_scale(img, paste0(round(plot_scale * 100), "%"))
}

img <- image_draw(img)

# plots used for the inverse transformation if necessary plotted as a cross
points(gcps$px * plot_scale, gcps$py * plot_scale, col = "blue", pch = 3, cex = 1)

# known locations plotted as a star with text
halo_star <- function(x, y, cex = 3) {
  points(x, y, pch = 8, cex = cex, col = "black", lwd = cex * 2)
  points(x, y, pch = 8, cex = cex * 0.85, col = "white", lwd = cex * 0.8)
}
halo_text <- function(x, y, labels, cex = 1.5, halo_width = 0.15) {
  offsets <- expand.grid(dx = c(-1, 0, 1), dy = c(-1, 0, 1))
  offsets <- offsets[!(offsets$dx == 0 & offsets$dy == 0), ]
  for (i in seq_len(nrow(offsets))) {
    text(x + offsets$dx[i] * halo_width * cex * 10, y + offsets$dy[i] * halo_width * cex * 10,
      labels = labels, col = "black", cex = cex, font = 2, pos = 4
    )
  }
  text(x, y, labels = labels, col = "white", cex = cex, font = 2, pos = 4)
}

for (cp in check_points) {
  result <- lonlat_to_pixel(cp$lon, cp$lat, coef_x, coef_y)
  halo_star(result$px * plot_scale, result$py * plot_scale)
  halo_text(result$px * plot_scale, result$py * plot_scale, cp$name)
  cat(sprintf(
    "%s (%.2fE, %.2fN) -> pixel (%.1f, %.1f)\n",
    cp$name, cp$lon, cp$lat, result$px, result$py
  ))
}

dev.off()

dir.create("outputs/checks", recursive = TRUE, showWarnings = FALSE)
out_path <- file.path("outputs/checks", paste0(tools::file_path_sans_ext(basename(map_path)), "_check_points.png"))
image_write(img, out_path, format = "png")
cat(sprintf("\nWrote %s -- confirm each cross lands on its named feature.\n", out_path))
