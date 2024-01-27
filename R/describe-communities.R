
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

communities <- read_sf(gpkg, "communities")

# join to watersheds ------------------------------------------------------

watersheds <- read_sf(gpkg, "HUC10")

pnts <- communities |> 
  select(id) |> 
  st_centroid() |> 
  st_join(watersheds["huc10"])

communities <- communities |> left_join(pnts, by = "id")

remove(pnts, watersheds)

# summarize terrain -------------------------------------------------------

# location of the virtual raster pointing to the 
# USGS one arc second elevation data (~30 m resolution)
elevation_source <- file.path(
  "https://prd-tnm.s3.amazonaws.com/StagedProducts",
  "Elevation/1/TIFF",
  "USGS_Seamless_DEM_1.vrt"
)

# need to access data from the virtual raster in chunks, 
# in this case HUC8s  
huc8 <- communities[["huc10"]] |> str_sub(1, 8) |> unique()

tmp_dir <- tempdir()

terrain_stats <- map(
  huc8, 
  \(x){
    
    tryCatch(
      summarize_terrain(
        elevation_source,
        features = communities |> filter(str_starts(huc10, x)),
        id_col = "id",
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

communities <- communities |> left_join(terrain_stats, by = "huc10")

write_sf(
  communities,
  dsn = gpkg,
  layer = "communities"
)

# add area estimate to non-spatial data table
communities |> 
  mutate(
    area_km2 = st_area(geom),
    area_km2 = units::set_units(area_km2, km2),
    area_km2 = units::drop_units(area_km2),
    .after = name
  ) |> 
  st_drop_geometry() |> 
  write_csv(here("data", "community-descriptions.csv"))