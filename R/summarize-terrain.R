#' Summarize terrain
#' 
#' Returns a table of terrain statistics, including average elevation and 
#' ruggedness and the proportion of the feature with slope below 5 degrees.
#'
#' @param x simple features
#' @param id_col character, name of column in features to use as ID in output
#' @param processing_dir character, just where to save a temporary file
#' 
#' @details
#' The great thing about using a VRT with COGs is that (a) you can use spatial
#' filters to limit how much data streams from the remote source to your local 
#' computer for a given operation and (b) you can do that by referencing a 
#' single source rather than having to loop over multiple grid tiles. 
#' 
#' But there is a trade-off: If you make your filters too small, you have to 
#' take more trips, which takes time. If you make the filters too big, you 
#' clobber your local memory. 
#' 
#' Here, we define a `processing directory` where you can temporarily store a
#' chunk of the virtual raster, process it, then overwrite it with the next
#' chunk. This is just so you don't have to dump a bunch of really big temp
#' files on your hard drive. 
#'
#' @return data.frame with four columns: id, elevation, ruggedness, and slope
#' 
summarize_terrain <- function(x, id_col, processing_dir = tempdir()){
  
  # location of the virtual raster pointing to the 
  # USGS one arc second elevation data (~30 m resolution)
  elevation_source <- file.path(
    "https://prd-tnm.s3.amazonaws.com/StagedProducts",
    "Elevation/1/TIFF",
    "USGS_Seamless_DEM_1.vrt"
  )
  
  # connect to vrt
  rr <- terra::rast(elevation_source, vsi = TRUE)
  
  # convert x to SpatVector and project to elevation crs
  features <- terra::vect(x)
  features <- terra::project(features, terra::crs(rr))
  
  # crop and save to disk, so we don't have to keep it all in memory
  rr <- terra::crop(
    rr, 
    features,
    snap = "out",
    mask = TRUE,
    filename = file.path(processing_dir, "temp-raster.tif"),
    datatype = "FLT4S",
    gdal = c("COMPRESS=DEFLATE", "ZLEVEL=9"),
    overwrite = TRUE
  )
  
  # compute terrain measures and stack
  rasters <- c(
    rr,
    terra::terrain(rr, "TRIrmsd"),
    terra::terrain(rr, "TPI"),
    terra::terrain(rr, "slope", unit = "degrees") <= 5
  )
  
  names(rasters) <- c("elevation", "tri_rmsd", "tpi", "p_flat")
  
  # extract values
  # uses weights to account for the approximate fraction of each cell that
  # falls into each polygon
  results <- terra::extract(
    rasters, 
    features, 
    fun = mean,
    weights = TRUE,
    na.rm = TRUE,
    ID = FALSE
  )
  
  results <- cbind(features[[id_col]], results)
  
  tibble::as_tibble(results)
  
}


