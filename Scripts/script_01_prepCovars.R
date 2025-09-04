#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Pronghorn RSF
# Leveraging WebGIS tools and existing agency monitoring data to efficiently
# map suitable habitat

# Jason Carlisle
# Wyoming Game and Fish Department

# Script 1 of 4:  Prep covariate rasters using MerkleLabGIS package
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Packages and CRS ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
require(sf)
require(terra)
require(dplyr)
require(ggplot2)
require(tidyterra)

# Install and load MerkleLabGIS package
require(remotes)
remotes::install_github("jmerkle1/MerkleLabGIS")
require(MerkleLabGIS)

# Master coordinate reference system to use for all spatial data
myCRS <- 26913  # https://spatialreference.org/ref/epsg/26913/


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Study area ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#

# Study area
aoi <- st_read(file.path("InputData",
                         "StudyArea_AllOwnership.kml")) |>
  st_transform(crs = myCRS)

plot(st_geometry(aoi))


# Store extent of aoi for map figures
aoi_bbox <- aoi |>
  st_bbox()


# Area to crop rasters to, the extent of the RSF to be produced
# The prepped rasters (projected, aligned cells, etc.) will have this extent
# The Random Forests prediction is easier if there are no NA cells (so don't
# download rasters using aoi borders directly or mask to the aoi borders)
aoi_rsf <- aoi |>
  st_buffer(dist = 1000) |>
  st_bbox() |>
  st_as_sfc() |>
  st_as_sf()


# Quick map
plot(st_geometry(aoi_rsf),
     lwd = 2,
     lty = "dotted",
     border = "darkgray",)
plot(st_geometry(aoi),
     lwd = 2,
     add = TRUE)


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Download covariate rasters ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# List available datasets
dt <- bucket()
nrow(dt)  # 1403 at time of writing, but subject to updates
table(dt$category)

# Layers to download
# Pronghorn survey was conducted in 2023, so select 2023 for time-varying data
toInclude <- c(
  "CTI_90m.tif",
  "DEM_100m.tif",
  "Slope_30m.tif",
  "HLI_90m.tif",
  "TRI_90m.tif",
  "TRI_990m.tif",
  "TPI_90m.tif",
  "TPI_990m.tif",
  "TRASP_90m.tif",
  "NHD_DistToStream.tif",
  "NHD_DistToWater.tif",
  "RAP_2023_Biomass_AnnualForbsGrasses.tif",
  "RAP_2023_Biomass_PerennialForbsGrasses.tif",
  "RAP_2023_Cover_BareGround.tif",
  "RAP_2023_Cover_Trees.tif",
  "RAP_2023_Cover_Shrubs.tif",
  "MOD09Q1_2023_MaxNDVIDay.tif",
  "MOD09Q1_2023_MaxIRGday.tif",
  "MOD09Q1_2023_SpringStartDay.tif",
  "MOD09Q1_2023_SpringLength.tif",
  "TIGER16_DistToRoads_PriSec_30m.tif",
  "snodas_annual_swe_all-years.tif" 
)

covars <- dt |>
  filter(filename %in% toInclude)

length(toInclude)  # 22
nrow(covars)  # 22


# Download rasters to memory (not file)
r <- CropRasters(cog_urls = covars$url,
                 polygon_sf = aoi_rsf,
                 writeData = FALSE)

length(r)  # 22
class(r)  # "list"


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Standardize rasters to same resolution, extent, origin ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# This step is not always needed.  But our goal is to create a predicted
# habitat suitability map using a Random Forests model.  That spatial prediction
# works best on a raster stack of covariates (predictor variables), and rasters
# need the same resolution, extent, and origin to be stacked.

# Raster names
(r_names <- sapply(r, names))

# Hopefully this is fixed soon, but as of writing (Aug 2025), the name of MODIS-derived datasets doesn't come through.  Add those manually.
# https://github.com/jmerkle1/MerkleLabGIS/issues/6
toSub <- which(grepl("MOD", covars$filename))

for (i in toSub) {
  names(r[[i]]) <- gsub(".tif", "", covars$filename[i])
}
(r_names <- sapply(r, names))


# Set the DEM as the master raster all others should match
plot(r[[which(r_names == "DEM_100m")]],
     main = "DEM - original CRS")
master <- r[[which(r_names == "DEM_100m")]] |>
  project(y = paste0("epsg:", myCRS))

# DEM raster info
master

# DEM - plot
plot(master,
     main = "DEM - new CRS")
lines(aoi,
      lwd = 2)


# Project and resample each raster to match the master raster
r <- lapply(r,
            function(i) {
              r <- i |>
                project(y = crs(master)) |>
                resample(y = master,
                         method = "bilinear",
                         threads = TRUE)
              return(r)
            })


# Check raster properties
sapply(r, res)
sapply(r, ext)


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Stack and save rasters ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#

# Stack the rasters. They must have the exact same properties (CRS, origin,
# resolution, extent) first

covars <- do.call(c, r)
class(covars)  # SpatRaster - terra


# SNODAS data comes as stack of multiple annual rasters
# Pronghorn survey was conducted in 2023, so select 2023 for time-varying data

nlyr(covars)  # expecting 22,but SWE for multiple years is included, so get 42
names(covars)

covars <- covars[[!(grepl("snodas", names(covars)) &
                        !grepl("2023", names(covars)))]]

nlyr(covars)  # 22
names(covars)


# Save all as RDS object
covars |>
  saveRDS(file.path("PreppedData",
                    "CovarRasters.rds"))


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Write out map figures ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#

# Write out a map figure of each covariate raster with the study area boundary
# Loop through each layer

for (i in 1:nlyr(covars)) {
  ggplot() +
    geom_spatraster(data = covars,
                    mapping = aes(fill = .data[[names(covars)[[i]]]]),
                    maxcell = ncell(covars)) +
    scale_fill_viridis_c(option = "mako",
                         direction = -1,
                         na.value = NA) +
    labs(fill = "",
         title = names(covars)[[i]]) +
    geom_sf(data = aoi,
            linewidth = 0.8,
            color = "black",
            alpha = 0) +
    coord_sf(crs = st_crs(myCRS),
             xlim = c(aoi_bbox$xmin, aoi_bbox$xmax),
             ylim = c(aoi_bbox$ymin, aoi_bbox$ymax)) +
    theme_bw() +
    theme(legend.position = "bottom",
          legend.key.width = unit(1, "null"),
          panel.grid = element_blank())

  ggsave(file.path("Output",
                   paste0("Covar_", names(covars)[[i]], ".png")),
         width = 4, height = 4, units = "in", dpi = 400)
}


# END