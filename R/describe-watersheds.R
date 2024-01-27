
library(arcgislayers)
library(here)
library(sf)
library(terra)
library(tidyverse)

# geopackage
gpkg <- here("data", "hndsr.gpkg")

here("R", "utils.R") |> source()

# turn off terra's progress bar
terraOptions(progress = 0)

# load watersheds ---------------------------------------------------------

watersheds <- read_sf(gpkg, "HUC10")

# summarize terrain -------------------------------------------------------

# location of the virtual raster pointing to the 
# USGS one arc second elevation data (~30 m resolution)
elevation_source <- file.path(
  "https://prd-tnm.s3.amazonaws.com/StagedProducts",
  "Elevation/1/TIFF",
  "USGS_Seamless_DEM_1.vrt"
)

# to make this easier on my local machine, need to access data from the 
# virtual raster in chunks, in this case HUC8s 
huc8 <- watersheds[["huc10"]] |> str_sub(1, 8) |> unique()

tmp_dir <- tempdir()

terrain_stats <- map(
  huc8, 
  \(x){
    
    tryCatch(
      summarize_terrain(
        elevation_source,
        features = watersheds |> filter(str_starts(huc10, x)),
        id_col = "huc10",
        processing_dir = tmp_dir
      ),
      error = function(e){ 
        cli::cli_alert("{x} failed!")
        return(NULL) 
      }
    )
    
  },
  .progress = TRUE
) |> bind_rows()

# extract data and save ---------------------------------------------------

watersheds <- watersheds |> left_join(terrain_statistics, by = "huc10")

write_sf(
  watersheds,
  dsn = gpkg,
  layer = "HUC10"
)

# add area estimate to non-spatial data table
watersheds |> 
  mutate(
    area_km2 = st_area(geom),
    area_km2 = units::set_units(area_km2, km2),
    area_km2 = units::drop_units(area_km2),
    .after = name
  ) |> 
  st_drop_geometry() |> 
  write_csv(here("data", "watershed-descriptions.csv"))