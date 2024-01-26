
#' Summarize terrain
#' 
#' Returns a table of terrain statistics, including average elevation and 
#' ruggedness and the proportion of the feature with slope below 5 degrees.
#'
#' @param x character, the url to the remote virtual raster
#' @param features simple feature geometry
#' @param id vector of IDs, should be same length as features
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
summarize_terrain <- function(x, features, id, processing_dir){
  
  rr <- terra::rast(x, vsi = TRUE)
  
  # convert sf to SpatVector and project to crs(x)
  feature <- terra::vect(features)
  feature <- terra::project(features, terra::crs(rr))
  
  # save to disk, so we don't have to keep it all in memory
  rr <- terra::crop(
    rr, 
    features,
    filename = file.path(processing_dir, "temp-raster.tif"),
    datatype = "FLT4S",
    gdal = c("COMPRESS=DEFLATE", "ZLEVEL=9"),
    overwrite = TRUE
  )

  # compute terrain measures and stack
  rasters <- c(
    rr,
    terra::terrain(rr, "TRIrmsd"),
    terra::terrain(rr, "slope", unit = "degrees") <= 5
  )
  
  names(rasters) <- c("elevation", "ruggedness", "slope")
  
  # extract values
  results <- terra::extract(
    rasters, 
    features, 
    fun = mean,
    weights = TRUE,
    na.rm = TRUE,
    ID = FALSE
  )
  
  cbind(id, results)
  
}


