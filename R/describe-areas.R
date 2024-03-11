
library(arcgislayers)
library(furrr)
library(here)
library(sf)
library(terra)
library(tidyverse)

# geopackage
gpkg <- here("data", "hndsr.gpkg")

# load main function for estimating terrain stats
here("R", "summarize-terrain.R") |> source()

# turn off terra's progress bar
terraOptions(progress = 0)

# number of workers to use for parallel processing
plan(multisession, workers = 4)

# Coordinate Reference System
# NAD83 (EPSG:4269)

# load features -----------------------------------------------------------

# huc10 watersheds
watersheds <- read_sf(gpkg, "HUC10")

# dispersed communities
communities <- read_sf(gpkg, "communities")

# get huc8 ----------------------------------------------------------------

# need to access data from the virtual raster in chunks, in this case HUC8s,  
# so we group and nest the data and map over the nests

watersheds <- watersheds |> mutate(huc8 = str_sub(huc10, 1, 8))

community_hucs <- communities |> 
  st_centroid() |> 
  st_join(watersheds["huc8"]) |> 
  st_drop_geometry() |> 
  select(id, huc8)

communities <- communities |> left_join(community_hucs, by = "id")

# summarize terrain -------------------------------------------------------

watershed_terrain <- watersheds |> 
  filter(huc8 %in% 13010001:13010004) |> 
  nest(.by = huc8) |> 
  pull(data) |> 
  future_map(\(x){ summarize_terrain(x, id_col = "huc10") }) |> 
  bind_rows()

community_terrain <- communities |> 
  nest(.by = huc8) |> 
  pull(data) |> 
  future_map(\(x){ summarize_terrain(x, id_col = "huc10") }) |> 
  bind_rows()

# extract data and save ---------------------------------------------------

watersheds <- watersheds |> left_join(watershed_terrain, by = "huc10")

write_sf(
  watersheds,
  dsn = gpkg,
  layer = "HUC10"
)

communities <- communities |> left_join(community_stats, by = "id")

write_sf(
  communities,
  dsn = gpkg,
  layer = "communities"
)

# add area estimate to non-spatial data table
watershed_data <- watersheds |> 
  mutate(
    level = "watershed",
    area_km2 = st_area(geom),
    area_km2 = units::set_units(area_km2, km2),
    area_km2 = units::drop_units(area_km2),
    .after = name
  ) |> 
  st_drop_geometry()

community_data <- communities |> 
  mutate(
    level = "community",
    area_km2 = st_area(geom),
    area_km2 = units::set_units(area_km2, km2),
    area_km2 = units::drop_units(area_km2),
    .after = name
  ) |> 
  st_drop_geometry()

bind_rows(
  watershed_data,
  community_data
) |> write_csv(here("data", "terrain-descriptions.csv"))