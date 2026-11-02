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

# # Purpose: Load libraries and authenticate with Google Analytics and shinyapps.io

# Packages installed from configured repositories
required_packages <- c(
  "googleAnalyticsR",
  "tidyverse",
  "lubridate",
  "zoo",
  "janitor",
  "slider",
  "rsconnect",
  "aws.s3",
  "glue",
  "ggplot2",
  "forcats",
  "quarto",
  "flexdashboard"
)

# Check for missing repository packages, and install if necessary
missing_packages <- setdiff(required_packages, rownames(installed.packages()))
if (length(missing_packages) > 0) {
  install.packages(missing_packages, dependencies = TRUE)
  missing_after <- setdiff(missing_packages, rownames(installed.packages()))
  if (length(missing_after) > 0) {
    stop(
      sprintf(
        "Failed to install packages: %s\nInstall them manually with install.packages(c(%s))",
        paste(missing_after, collapse = ", "),
        paste(sprintf('"%s"', missing_after), collapse = ", ")
      ),
      call. = FALSE
    )
  }
}

# Install safepaths from GitHub if it is missing.
if (!requireNamespace("safepaths", quietly = TRUE)) {
  if (!requireNamespace("remotes", quietly = TRUE)) {
    install.packages("remotes")
  }
  if (!requireNamespace("remotes", quietly = TRUE)) {
    stop(
      "Failed to install 'remotes', which is needed to install 'safepaths'.",
      call. = FALSE
    )
  }
  remotes::install_github("bcgov/safepaths", dependencies = TRUE)
  if (!requireNamespace("safepaths", quietly = TRUE)) {
    stop("Failed to install 'safepaths' from bcgov/safepaths.", call. = FALSE)
  }
}

library(googleAnalyticsR)
library(rsconnect)
library(aws.s3)
library(tidyverse)
library(lubridate)
library(zoo)
library(janitor)
library(slider)
library(safepaths)
library(glue)
library(ggplot2)
library(forcats)
library(quarto)
library(flexdashboard)

base_reports <- c("pageview", "click", "referurl", "platform", "geoloc")
extra_reports <- c("asset", "search", "google")

source("R/functions/month-run-helpers.R")
source("R/functions/gdx-web-analysis-functions.R")

# The ".Renviron" file will be stored on LAN so that people can load

# File paths (LAN) setup
LAN_FOLDER <- use_network_path()
# if 'Error:! There has been a problem. Are you sure you are connected to the VPN?'
# connect to VPN and manually double click the 'network drive' in 'This PC' in Windows Explorer to ensure it's connected (green), then run this code again
# double-check your drive mapping in .Renviron; if it's wrong, correct it, close RStudio and start fresh
PROJECT_ROOT <- glue(
  "{LAN_FOLDER}/0. Misc/Data Science Tooling/web-hosting-and-dashboards/shinyapps_webtraffic_monitoring"
)
DATA_RAW <- glue("{PROJECT_ROOT}/data")
OUTPUT_TABLES <- glue("{PROJECT_ROOT}/outputs/tables")
OUTPUT_VISUALS <- glue("{PROJECT_ROOT}/outputs/visuals")
OUTPUT_REPORTS <- glue("{PROJECT_ROOT}/outputs/reports")

# Create directories if they don't exist
paths_to_create <- c(DATA_RAW, OUTPUT_TABLES, OUTPUT_VISUALS, OUTPUT_REPORTS)
for (p in paths_to_create) {
  if (!dir.exists(p)) {
    dir.create(p, recursive = TRUE, showWarnings = FALSE)
  }
}


# and do the code review with access to the credentials, but the file itself
# will not be committed to GitHub. Each user can create their own ".Renviron" file
#  with the same variable names but different values
# (e.g., for GA service account key path) if needed.

# Helpers functions to read environment variables
require_env <- function(name) {
  val <- Sys.getenv(name, unset = "")
  if (!nzchar(val)) {
    stop(
      sprintf("Missing required environment variable: %s", name),
      call. = FALSE
    )
  }
  val
}

optional_env <- function(name, default = NA_character_) {
  val <- Sys.getenv(name, unset = "")
  if (!nzchar(val)) default else val
}

# Set EXTRA_RENVIRON_PATH only when needed (e.g., on a server)
extra_renviron <- Sys.getenv("EXTRA_RENVIRON_PATH", unset = "")
if (nzchar(extra_renviron) && file.exists(extra_renviron)) {
  readRenviron(extra_renviron)
}

#  Configuration (prefer env vars)
GA_PROPERTY_ID <- optional_env("GA_PROPERTY_ID", default = "394480605")
GA_DATE_START <- optional_env("GA_DATE_START", default = "2024-01-01")
GA_DATE_END <- optional_env(
  "GA_DATE_END",
  default = as.character(Sys.Date() - 1)
) # default to yesterday to avoid partial current-day data

#  GA Service Account Auth
# Copy the service account JSON key from LAN into your local cloned repo as
# ga-auth-key.json (ignored by Git)
GA_SERVICE_EMAIL <- require_env("GA_SERVICE_EMAIL")
GA_SERVICE_KEY <- require_env("GA_SERVICE_KEY") # full path to JSON key file

if (!file.exists(GA_SERVICE_KEY)) {
  stop(
    sprintf("GA service account key JSON not found at: %s", GA_SERVICE_KEY),
    call. = FALSE
  )
}

ga_auth(
  email = GA_SERVICE_EMAIL,
  json_file = GA_SERVICE_KEY
)

#  shinyapps.io Auth
setAccountInfo(
  name = require_env("SHINY_ACC_NAME"),
  token = require_env("SHINY_TOKEN"),
  secret = require_env("SHINY_SECRET")
)
