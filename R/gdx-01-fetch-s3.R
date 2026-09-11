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

source("R/00-setup.R")
source("R/functions/month-run-helpers.R")

library(aws.s3)

# Step 1: Read required environment variables once
env_keys <- c(
  "AWS_ACCESS_KEY_ID",
  "AWS_SECRET_ACCESS_KEY",
  "AWS_DEFAULT_REGION",
  "BCSTATS_S3_BUCKET",
  "BCSTATS_S3_PREFIX"
)

env_values <- Sys.getenv(env_keys, unset = NA_character_)
names(env_values) <- env_keys

# Step 2: Validate missing values
missing_env <- names(env_values)[is.na(env_values) | env_values == ""]
if (length(missing_env) > 0) {
  stop(
    sprintf(
      "Missing environment variables: %s",
      paste(missing_env, collapse = ", ")
    ),
    call. = FALSE
  )
}

# Step 3: Assign name variables from environment values for easier reference.
bucket <- env_values[["BCSTATS_S3_BUCKET"]]
prefix <- env_values[["BCSTATS_S3_PREFIX"]]
region <- env_values[["AWS_DEFAULT_REGION"]]

# Optional source subfolder selector for controlled ingestion from S3.
# Example: Sys.setenv(BCSTATS_S3_SOURCE_SUBFOLDER = "UAT_20260720")
source_subfolder <- Sys.getenv("BCSTATS_S3_SOURCE_SUBFOLDER", unset = "")
if (nzchar(source_subfolder)) {
  source_subfolder <- str_remove(source_subfolder, "^/")
  source_subfolder <- str_remove(source_subfolder, "/$")
}

# Optional regex selector applied to the key relative to the configured prefix.
# Needed for the report-specific structure ({report}/v00_manual, {report}/v01_auto),
# where a reporting month is identified by generation timestamp rather than folder.
# Example: Sys.setenv(BCSTATS_S3_KEY_PATTERN = "/v01_auto/.*_20260910T0[12]")
key_pattern <- Sys.getenv("BCSTATS_S3_KEY_PATTERN", unset = "")

# Step 4: Resolve target month (default: previous month).
# Override with env var GDX_TARGET_MONTH=YYYY-MM when needed.
target_month <- resolve_target_month(mode = "previous")
target_dir <- file.path(DATA_RAW, "cms_lite", target_month)

dir.create(
  target_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# Step 5: List objects from the target S3 prefix.
objects <- get_bucket(
  bucket = bucket,
  prefix = prefix,
  region = region
)

# Step 6: Convert S3 object metadata to a table and keep only CSV data files.
file_index <- data.frame(
  key = vapply(objects, function(x) as.character(x$Key), character(1)),
  size = vapply(objects, function(x) as.numeric(x$Size), numeric(1)),
  last_modified = as.POSIXct(
    vapply(objects, function(x) as.character(x$LastModified), character(1)),
    format = "%Y-%m-%dT%H:%M:%OSZ",
    tz = "UTC"
  ),
  stringsAsFactors = FALSE
) |>
  mutate(
    # Normalize key relative to configured prefix for folder filtering and checks.
    key_rel = str_remove(key, paste0("^", fixed(prefix))),
    key_rel = str_remove(key_rel, "^/")
  )

data_files <- file_index |>
  filter(
    !is.na(key),
    size > 0,
    str_starts(key, prefix),
    str_detect(key, "\\.csv$")
  )

if (nzchar(source_subfolder)) {
  data_files <- data_files |>
    filter(str_starts(key_rel, paste0(source_subfolder, "/")))
}

if (nzchar(key_pattern)) {
  data_files <- data_files |>
    filter(str_detect(key_rel, key_pattern))
}

# Guard against basename collisions from multi-folder drops.
# If duplicates exist, stop and require a single source subfolder selection.
basename_dups <- data_files |>
  mutate(file = basename(key)) |>
  count(file, sort = TRUE) |>
  filter(n > 1)

if (nrow(basename_dups) > 0) {
  stop(
    paste0(
      "Detected duplicate basenames in selected S3 files (first 10): ",
      paste(head(basename_dups$file, 10), collapse = ", "),
      ". Set BCSTATS_S3_SOURCE_SUBFOLDER to a single drop folder (e.g. UAT_20260720)."
    ),
    call. = FALSE
  )
}

if (nrow(data_files) == 0) {
  stop("No CSV files found in S3 prefix.", call. = FALSE)
}

# Step 7: Download all CSVs into DATA_RAW/cms_lite/<target_month>.
walk(data_files$key, \(key) {
  save_object(
    object = key,
    bucket = bucket,
    file = file.path(target_dir, basename(key)),
    region = region
  )
})

# Step 8: Validate that expected monthly report families are present.
assert_cmslite_reports_present(target_dir)

message(sprintf(
  "Month %s: downloaded %s CSV file(s) from prefix '%s'%s to: %s",
  target_month,
  nrow(data_files),
  prefix,
  if (nzchar(source_subfolder)) {
    paste0(" (subfolder=", source_subfolder, ")")
  } else {
    ""
  },
  target_dir
))
