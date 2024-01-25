
library(arcgislayers)
library(here)
library(sf)
library(tidyverse)

# geopackage
gpkg <- here("data", "hndsr.gpkg")

# HUC10 watersheds selected by PIs
selection <- here("data", "selected-watersheds.txt") |> 
  readLines() |> 
  str_split_1(", ") |>
  as.numeric()

# load watersheds ---------------------------------------------------------

nhd_plus <- file.path(
  "https://hydro.nationalmap.gov/arcgis/rest/services",
  "NHDPlus_HR",
  "MapServer"
) |> arc_open()

get_huc12 <- function(x, server = nhd_plus){
  
  server |> 
    get_layer(name = "WBDHU12") |> 
    arc_select(
      fields = c("huc12", "name"),
      where = paste0("huc12 LIKE '", x, "%'"),
      geometry = TRUE
    )
  
}

# map over selections
huc12 <- selection |> 
  str_sub(1, 8) |> 
  unique() |> 
  map(get_huc12) |> 
  bind_rows()

# filter join to remove watersheds not in selection
huc12 <- huc12 |> 
  mutate(
    huc10 = str_sub(huc12, 1, 10), 
    .before = "huc12"
  ) |> 
  semi_join(
    tibble(huc10 = as.character(selection)),
    by = "huc10"
  )

# currently stored as MULTIPOLYGON, but none of them
# are actually MULTIPOLYGON, so cast to POLYGON
huc12 <- huc12 |> 
  st_cast("POLYGON") |> 
  arrange(huc10, huc12)

remove(selection, get_huc12)

# aggregate to HUC10 ------------------------------------------------------

huc10 <- huc12 |> 
  group_by(huc10) |> 
  summarize()

# want to add colloquial name for no good reason, so...
wbd <- file.path(
  "https://hydro.nationalmap.gov/arcgis/rest/services",
  "wbd",
  "MapServer"
) |> arc_open()

# REST API is fickle, so this doesn't always work
huc10_names <- wbd |> 
  get_layer(5) |> 
  arc_select(
    fields = c("huc10", "name"),
    filter_geom = st_union(huc10),
    geometry = FALSE
  )

huc10 <- huc10 |> 
  left_join(huc10_names, by = "huc10") |> 
  relocate(name, .after = "huc10")

remove(huc12, wbd, huc10_names)

# split watersheds on river -----------------------------------------------

# they did things differently north of the colorado...

# download colorado river lines
nhd <- file.path(
  "https://hydro.nationalmap.gov/arcgis/rest/services",
  "nhd",
  "MapServer"
) |> arc_open()

# the colorado only crosses the northwest part of the study area...
border_watersheds <- huc10 |> 
  filter(str_sub(huc10, 1, 4) %in% c(1407, 1501))

colorado_river <- nhd |> 
  get_layer(6) |> 
  arc_select(
    where = "gnis_name = 'Colorado River'",
    filter_geom = st_union(border_watersheds),
    geometry = TRUE
  )

cut_hydro <- function(x, river, side){
  
  suppressWarnings({
    
    shp <- st_union(x) |>
      lwgeom::st_split(river) |>
      st_collection_extract("POLYGON") |>
      st_make_valid()
    
    st_intersection(x, shp[side])
    
  })
  
}

huc10 <- huc10 |> cut_hydro(colorado_river, 1)

remove(nhd, border_watersheds, cut_hydro)

# build project window ----------------------------------------------------

project_area <- huc10 |> st_union()

# union introduces holes, probably because the vertices are super dense
project_area <- st_polygon(project_area[[1]][1])
  
project_area <- st_sf(
  name = "NSF HNDS-R Project Area",
  geometry = st_sfc(project_area),
  crs = st_crs(huc10)
)

# transform and save results ----------------------------------------------

project_area <- project_area |> st_transform(4326)

write_sf(
  project_area,
  dsn = gpkg,
  layer = "window"
)

huc10 <- huc10 |> st_transform(4326)

write_sf(
  huc10, 
  dsn = gpkg,
  layer = "HUC10"
)
