
library(arcgislayers)
library(furrr)
library(here)
library(sf)
library(terra)
library(tidyverse)

# load main function for estimating terrain stats
here("R", "describe.R") |> source()

# turn off terra's progress bar
terraOptions(progress = 0)

# number of workers to use for parallel processing
plan(multisession, workers = 4)

# Coordinate Reference System
# NAD83 (EPSG:4269)

# load features -----------------------------------------------------------

# individual sites
sites <- here("data", "site-points.csv") |> 
  read_csv() |> 
  rename_with(str_remove, pattern = "s.") |> 
  st_as_sf(
    coords = c("longitude", "latitude"), 
    crs = 4326
  ) |> 
  st_transform(4269)

# summarize terrain -------------------------------------------------------

# here we chunk the data by county and loop over the chunks

site_stats <- sites |> 
  # using 2km buffer
  st_buffer(2000) |> 
  nest(.by = county) |> 
  mutate(terrain = future_map(data, \(x){ describe(x, id_col = "temp_id") })) |> 
  select(terrain) |> 
  unnest(terrain)

# extract data and save ---------------------------------------------------

sites |> 
  st_drop_geometry() |> 
  left_join(site_stats, by = "temp_id") |> 
  mutate(
    level = "site",
    area_km2 = 4 * pi,
    .after = name
  ) |> 
  write_csv(here("data", "site-descriptions.csv"))
