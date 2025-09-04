#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Pronghorn RSF
# Leveraging WebGIS tools and existing agency monitoring data to efficiently
# map suitable habitat

# Jason Carlisle
# Wyoming Game and Fish Department

# Script 2 of 4:  Prep presence and (pseudo-)absence points
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Packages, CRS, and random seed ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
require(sf)
require(terra)
require(dplyr)
require(ggplot2)

# Master coordinate reference system to use for all spatial data
myCRS <- 26913

# Set seed to make random pseudo-absence points reproducible
set.seed(82071)


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Study area ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Portion of Medicine Bow herd unit
aoi <- st_read(file.path("InputData",
                                "StudyArea_AllOwnership.kml")) |>
  st_transform(crs = myCRS)


# Public land in the study area
aoi_public <- st_read(file.path("InputData",
                            "StudyArea_Public.kml")) |>
  st_transform(crs = myCRS)


# Quick map
plot(st_geometry(aoi_public), col = "lightgrey", border = FALSE)
plot(st_geometry(aoi), lwd = 3, add = TRUE)


# Store extent of aoi for map figures
aoi_bbox <- aoi |>
  st_bbox()

#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Pronghorn locations from aerial line transect (LT) survey ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# LT lines surveyed
l <- st_read(file.path("InputData",
                       "SurveyData_TransectLines.kml")) |>
  st_transform(myCRS) |>
  select(geometry)


# LT observations
pts <- st_read(file.path("InputData",
                         "SurveyData_PronghornPoints.kml")) |>
  st_transform(myCRS) |>
  mutate(PresAbs = 1) |>
  select(PresAbs, geometry)
nrow(pts)  # 188


# Quick map
plot(st_geometry(aoi_public), col = "lightgrey", border = FALSE)
plot(st_geometry(aoi), lwd = 3, add = TRUE)
plot(st_geometry(l), col = "blue", lwd = 2, add = TRUE)
plot(st_geometry(pts), col = "blue", cex = 1.5, add = TRUE)


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Random pseudo-absence points ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#

# Random sample (same number as presence points)
# Allow anywhere on public land in aoi
pts_rando <- st_sf(PresAbs = 0,
                   geometry = st_sample(aoi_public,
                                        size = nrow(pts)))

# Quick map
plot(st_geometry(aoi_public), col = "lightgrey", border = FALSE)
plot(st_geometry(aoi), lwd = 3, add = TRUE)
plot(st_geometry(l), col = "blue", lwd = 2, add = TRUE)
plot(st_geometry(pts), col = "blue", cex = 1.5, add = TRUE)
plot(st_geometry(pts_rando), col = "red", cex = 1.5, add = TRUE)


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Combine and save spatial points ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
pts <- pts |>
  bind_rows(pts_rando)

nrow(pts)  # 376
table(pts$PresAbs)
# 0   1 
# 188 188

# Write presence / absence points
pts |>
  saveRDS(file.path("PreppedData",
                    "Pronghorn_PresAbs.rds"))


#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#
# Write out map figures ----
#%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#

ggplot() +
  geom_sf(data = l,
          linewidth = 0.25,
          color = "grey50") +
  geom_sf(data = aoi,
          linewidth = 0.8,
          color = "black",
          alpha = 0) +
  geom_sf(data = pts,
          mapping = aes(color = factor(PresAbs, levels = c("1", "0"))),
          pch = 19,
          size = 0.75) +
  coord_sf(crs = st_crs(myCRS),
           xlim = c(aoi_bbox$xmin, aoi_bbox$xmax),
           ylim = c(aoi_bbox$ymin, aoi_bbox$ymax)) +
  scale_color_manual(values = c("black", "pink"),
                     labels = c("Presence", "Pseudo-absence")) +
  labs(color = "",
       title = "Pronghorn locations") +
  theme_bw() +
  theme(legend.position = "bottom",
        panel.grid = element_blank())

ggsave(file.path("Output",
                 "PresAbs.png"),
       width = 4, height = 4, units = "in", dpi = 400)


# END