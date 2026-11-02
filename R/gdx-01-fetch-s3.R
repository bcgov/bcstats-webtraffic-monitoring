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

# Purpose: Download monthly report CSVs from S3 to the local raw-data directory.

# Keep this so the fetch step can also be sourced independently of the pipeline.
source("R/00-setup.R")

# Validate S3 settings even when this script is run on its own.
s3_config <- get_s3_config(require_credentials = TRUE)
bucket <- s3_config$bucket
prefix <- s3_config$prefix
region <- s3_config$region

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

# The monthly pipeline supplies target_month; resolve it only for standalone runs.
if (!exists("target_month", inherits = FALSE)) {
  target_month <- resolve_target_month(mode = "previous")
}
target_dir <- file.path(DATA_RAW, "cms_lite", target_month)

# List once and validate the selection before changing local files.
objects <- get_bucket(
  bucket = bucket,
  prefix = prefix,
  region = region,
  max = Inf
)

# Convert S3 object metadata to a table and keep only CSV data files.
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
  stop(
    sprintf(
      "No S3 files matched the selection for %s. Upstream files may not be published yet.",
      target_month
    ),
    call. = FALSE
  )
}

# Reject multiple runs of the same report even when filenames differ by timestamp.
duplicate_reports <- data_files |>
  mutate(
    report = str_extract(
      basename(key),
      "webdata_bcstats_[a-z]+_[a-z]+_monthly"
    ),
    part = str_extract(basename(key), "part\\d{3}")
  ) |>
  count(report, part, sort = TRUE) |>
  filter(n > 1)

if (nrow(duplicate_reports) > 0) {
  stop(
    paste0(
      "Selection matched multiple runs for the same report(s): ",
      paste(head(duplicate_reports$report, 10), collapse = ", "),
      ". Narrow BCSTATS_S3_KEY_PATTERN to a single run."
    ),
    call. = FALSE
  )
}

message(sprintf(
  "Pre-flight: %s file(s) selected for %s.",
  nrow(data_files),
  target_month
))

dir.create(target_dir, recursive = TRUE, showWarnings = FALSE)

# Remove old CSVs only after the new selection passes validation.
old_csvs <- list.files(target_dir, pattern = "\\.csv$", full.names = TRUE)
if (length(old_csvs) > 0) {
  unlink(old_csvs)
}

# Download all CSVs into DATA_RAW/cms_lite/<target_month>.
walk(data_files$key, \(key) {
  save_object(
    object = key,
    bucket = bucket,
    file = file.path(target_dir, basename(key)),
    region = region
  )
})

# Validate that expected monthly report families are present.
assert_cmslite_reports_present(target_dir)

message(sprintf(
  "S3 download successful for month %s: %s CSV file(s) from prefix '%s'%s to: %s",
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
