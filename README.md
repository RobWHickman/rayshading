# Georeferencing historical maps for rayshader

General QGIS + R workflow for georeferencing scanned maps (old
non-standard grids, Ordnance Survey grid maps, etc.) so a DEM can be
draped under them and rendered with R/rayshader. Worked example and
full narrative for the first map done this way: see
[georeferencing_handoff.md](georeferencing_handoff.md). This README is
the reusable how-to — keep it map-agnostic; per-map values (GCPs,
raster path, check-point cities) go in `configs/<map_name>.R`, not in
the scripts or here.

## Files

- `inputs/original_maps/` — source scans.
- `inputs/georeferences/` — georeferenced raster outputs (`*.tif`) per
  map, native pixel grid, untouched border.
- `configs/_template.R` — blank config template (`map_path`, `gcps`,
  `check_points`). Copy per map, see instructions inside. Only this
  template is committed — `configs/*.R` copies are gitignored.
- `src/gcp_transform.R` — shared polynomial fit/eval functions.
- `src/inverse_transform.R` — generic script: fits lon/lat → map-pixel
  polynomial from a config's GCPs, used to warp a DEM onto a map's
  native pixel grid. Only needed for curved/non-straight grids (see
  Step 0). Run: `Rscript src/inverse_transform.R configs/<map_name>.R`
- `src/plot_check_points.R` — generic script, validation check 1 from
  Step 5: plots the map raster with the config's check-point cities
  and GCPs overlaid, so you can eyeball whether they land in the right
  place. Run: `Rscript src/plot_check_points.R configs/<map_name>.R
  [plot_scale]` — output always goes to
  `outputs/checks/<map_name>_check_points.png` (gitignored).

## Step 0 — check the grid type first

Before touching QGIS: zoom into the map's grid (graticule, national
grid, whatever it carries) and check whether it's straight or curved.

- **Straight, evenly spaced anywhere on the sheet** (plate carrée, OS
  National Grid, UTM, etc.) → corner coordinates + `gdal_translate
  -a_ullr -a_srs`, done in minutes. No polynomial fit needed, skip
  `inverse_transform.R`.
- **Meridian/line spacing changes with position, or lines are curved**
  → conic-family or other non-linear projection. Needs the full GCP +
  polynomial workflow below. Budget a full session.
- **No grid at all** → fall back to coastline/landmark GCPs (least
  reliable).

Detection method (pixel-per-degree spacing check, offset vs. curvature
distinction) is worked through in the handoff doc.

## Step 1 — set up a clean pixel grid

JPEG DPI metadata can make QGIS misread raw pixel coordinates. Force a
1-unit-per-pixel geotransform before reading any pixel positions:

```bash
gdalinfo scan.tif   # note Size: <width>, <height>
gdal_translate -a_srs none -a_ullr 0 0 <width> <height> scan.tif scan_pixelgrid.tif
```

Always read pixel coordinates off `scan_pixelgrid.tif`, not the
original.

**Sign gotcha:** QGIS's status bar shows pixel row as negative
(e.g. `-762.90`). Drop the sign for the true row index.

## Step 2 — collect GCPs

For each reference point (grid crossings, known landmarks):

1. Hover the point on `scan_pixelgrid.tif`, read pixel col/row off the
   status bar (row = abs(negative value)).
2. Read the nearest grid value from the map margin/labels.
3. Convert to real lon/lat (or easting/northing) as needed for that
   map's coordinate system and reference. Some 19th-century maps use a
   historical reference meridian instead of Greenwich (e.g. Ferro,
   20° west of Paris ≈ 17.6628°W of Greenwich) — check the map's
   legend/margin, and record whatever conversion applies for the map
   at hand in your working notes, not in this script.

Spread points across all four quadrants of the sheet, not just the
corners — needed to constrain a polynomial fit against curvature, if
the grid turned out to be curved in Step 0.

## Step 3 — forward georeferencing (map pixel → lon/lat)

`Layer → Georeferencer` (enable via `Plugins → Manage and Install
Plugins → Georeferencer GDAL` if missing).

1. **Add Point** → click pixel on raster → enter the converted
   real-world coordinate, with per-point CRS set to the target CRS
   (e.g. EPSG:4326, or the relevant national grid CRS).
2. Check the GCP table's residual column. If corner residuals are much
   worse than central ones, the default Linear (Helmert) transform
   can't handle the curvature.
3. **Settings → Transformation Settings** → for a curved grid, set
   Transformation type to **Polynomial 2** (needs 6+ points); for a
   straight grid this step isn't needed at all (see Step 0).
4. Leave "Set target resolution" **unchecked** — placeholder values
   there produce a degenerate output ("Transform Failed").
5. **Start Georeferencing** → warped GeoTIFF in the target CRS. For a
   conic source, expect a "pincushion" bowed-corner shape when unwarped
   into a flat CRS — that's correct, not an artifact.

## Step 4 — reverse direction (lon/lat → map's own pixel grid)

Warping the map itself destroys its rectangular border. Better: keep
the map raster untouched and warp the **DEM** onto the map's native
pixel grid instead. Only needed for curved grids — for a straight grid,
Step 3's affine transform is already invertible with plain GDAL.

1. Fill in `gcps` in `configs/<map_name>.R` for this map, then run
   `Rscript src/inverse_transform.R configs/<map_name>.R` to fit a
   degree-2 polynomial (same basis as QGIS's Polynomial 2) and get
   predicted pixel (x, y) for each GCP's lon/lat.
2. In the Georeferencer's GCP table, edit the **Dest X/Y** columns to
   these predicted pixel values, keeping Source X/Y as the original
   scan pixel coordinates.
3. Target CRS must be a **projected/linear** CRS (e.g. EPSG:3857) —
   used only as a Cartesian number carrier, not for its real semantics.
4. **Negate Dest Y** before entering it (`-row`). Projected CRSs treat
   increasing Y as north/up; raw pixel rows increase downward. Skipping
   this produces an upside-down result.
5. Output is a raster living in the historical map's native pixel grid
   — the resampling target for the actual DEM.

## Step 5 — validate

Two checks:

1. **Check-point overlay** — run `src/plot_check_points.R
   configs/<map_name>.R` to plot the config's check-point cities and
   GCPs over the original scan, and confirm by eye that they land on
   the real features.
2. **Hillshade-vs-hachure overlay** (not yet automated) — `gdaldem
   hillshade` the DEM once it's on the map's pixel grid, blend over the
   historical map at partial opacity, check computed ridgelines align
   with the map's own drawn relief (hachures, contours, whatever it
   uses).

## Downstream (R / rayshader)

Since the DEM ends up resampled onto the map's exact native pixel grid,
the R side needs no further alignment between DEM and map raster for
any given map — they already share pixel dimensions and stack directly.
