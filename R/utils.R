
#' Get summary value in polygon
#' 
#' This is a vectorized version of `terra::extract()` designed to work 
#' within `{dplyr}` verbs.
#'
#' @param x a `SpatRaster`
#' @param geometry an `sfc` list
#' @param .f a function to summarize values in polygon, default is `median()`
#' @param ... additional arguments to be passed on to `.f`, e.g., `na.rm = TRUE`
#'
#' @return a vector of summary values for each feature in `geometry`
#'
get_value <- function(x, geometry, .f = median, ...){
  
  terra::extract(
    x, 
    geometry, 
    fun = .f,
    ...
  )[["value"]]
  
}