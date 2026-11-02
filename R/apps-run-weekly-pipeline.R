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

# Purpose: Master pipeline script. Fetches new data, analyzes usage,
# renders the dashboard, and archives the report to the production folder.

source("R/00-setup.R")

# ==============================================================================
# STEP 1 & 2: FETCH NEW DATA AND GENERATE SUMMARIES
# ==============================================================================
message("Step 1: Fetching latest GA4 data...")
source("R/apps-02-fetch-ga-weekly.R")

message("Step 2: Analyzing usage and updating summary tables...")
source("R/apps-04-analyze-usage.R")


# ==============================================================================
# STEP 3: DETERMINE LATEST WEEK FOR REPORT FILENAME
# ==============================================================================
message("Step 3: Calculating report filename...")

weekly_usage <- read_csv(
  file.path(OUTPUT_TABLES, "weekly_usage.csv"),
  show_col_types = FALSE
)
daily_usage_raw <- readRDS(file.path(DATA_RAW, "daily_usage_raw.rds"))

# Get the latest ISO week string (e.g., "202617")
latest_week <- max(weekly_usage$isoYearIsoWeek, na.rm = TRUE)

# Find the Monday date of that exact week directly from your raw data
#   1. filter() -> Shrink the daily data down to ONLY the 7 days in our target week.
#   2. pull()   -> Extract just the list of dates from those 7 days.
#   3. min()    -> Grab the earliest date. Since ISO weeks run Mon-Sun,
#                  the earliest date in this group is guaranteed to be Monday!
latest_week_date <- daily_usage_raw |>
  filter(format(as.Date(date), "%G%V") == latest_week) |>
  pull(date) |>
  min(na.rm = TRUE) |>
  as.Date()

# Format the date for the filename (e.g., "2026-04-20")
date_suffix <- format(latest_week_date, "%Y-%m-%d")


# ==============================================================================
# STEP 4: RENDER THE DASHBOARD
# ==============================================================================
message("Step 4: Rendering Quarto dashboard...")

# This generates the default "Report/dashboard.html"
quarto_render("Report/shinyapps_dashboard.qmd")


# ==============================================================================
# STEP 5: MOVE AND RENAME OUTPUT
# ==============================================================================
message("Step 5: Archiving output file...")

source_file <- "Report/dashboard.html"
final_file_name <- glue("Traffic_Snapshot_Week_Of_{date_suffix}.html")
dest_file <- file.path(OUTPUT_REPORTS, final_file_name)

message(glue("Moving dashboard to: {dest_file}"))

# Safely copy and remove to bypass network drive constraints
file.copy(from = source_file, to = dest_file, overwrite = TRUE)
file.remove(source_file)

message(
  "Success! The weekly data pipeline is complete and the dashboard is ready."
)
