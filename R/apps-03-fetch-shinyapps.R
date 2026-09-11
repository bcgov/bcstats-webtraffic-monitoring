# Copyright 2026 Province of British Columbia
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Purpose: Download shinyapps.io metrics (concurrency) and save locally

source("R/00-setup.R")


#  Get the list of all apps
# This hits the shinyapps.io API and returns a data frame
my_apps_df <- applications()

# Only 11 apps are kept since other apps are archived or private
# name
# Economic-Indicators
# hsdProjApp
# popApp
# sb-profile
# CountryTradeApp
# LAEP
# bc-demographic-survey-dip-data-linkage-rates
# interprovincial_migration_bc
# RetailSalesApp
# so_data_viewer
# LFS_app
target_app_names <- c(
  "Economic-Indicators",
  "hsdProjApp",
  "popApp",
  "sb-profile",
  "CountryTradeApp",
  "LAEP",
  "bc-demographic-survey-dip-data-linkage-rates",
  "interprovincial_migration_bc",
  "RetailSalesApp",
  "so_data_viewer",
  "LFS_app"
)

apps_11 <- my_apps_df |>
  filter(name %in% target_app_names) |>
  select(id, name, url, status)


#  Function to get concurrency for one app
get_concurrency_metrics <- function(app_name, interval) {
  metrics <- showMetrics(
    appName = app_name,
    metricSeries = "container_status",
    metricNames = "connect_count",
    from = "90d",
    interval = interval,
    server = "shinyapps.io"
  )

  metrics_tbl <- metrics |> as_tibble()

  time_col <- names(metrics_tbl)[
    map_lgl(metrics_tbl, ~ inherits(.x, c("POSIXct", "POSIXt", "Date")))
  ][1]

  if (is.na(time_col)) {
    time_col <- names(metrics_tbl)[str_detect(names(metrics_tbl), "time|date")][
      1
    ]
  }

  value_col <- names(metrics_tbl)[
    map_lgl(metrics_tbl, is.numeric)
  ][1]

  if (is.na(time_col) || is.na(value_col)) {
    stop(
      "Expected time/value columns not found in showMetrics output.",
      call. = FALSE
    )
  }

  metrics_tbl |>
    mutate(
      app_name = app_name,
      interval = interval
    ) |>
    rename(
      time = !!sym(time_col),
      concurrent_users = !!sym(value_col)
    ) |>
    select(app_name, interval, time, concurrent_users)
}

# interval can be "1m" (1 minute), "5m" (5 minutes), "1h" (1 hour)
intervals <- c("1m", "5m", "1h")

# Loop through apps and intervals to get concurrency metrics
all_concurrency <- expand_grid(
  app_name = target_app_names,
  interval = intervals
) |>
  mutate(data = map2(app_name, interval, get_concurrency_metrics)) |>
  select(data) |>
  unnest(data)

saveRDS(
  all_concurrency,
  file = file.path(DATA_RAW, "shinyapps_concurrency.rds")
)
