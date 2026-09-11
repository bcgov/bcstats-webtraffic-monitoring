# One-click monthly pipeline for GDX web dashboard
# Default behavior: process previous calendar month.
# Optional explicit month override: Sys.setenv(GDX_TARGET_MONTH = "YYYY-MM")

source("R/00-setup.R")
source("R/functions/month-run-helpers.R")

library(dplyr)
library(stringr)
library(aws.s3)

# Resolve target month for this run.
# If GDX_TARGET_MONTH is set, use it; otherwise force previous calendar month.
env_month <- Sys.getenv("GDX_TARGET_MONTH", unset = "")
target_month <- if (nzchar(env_month)) {
  resolve_target_month(month = env_month, mode = "explicit")
} else {
  prev_month <- format(
    seq.Date(
      as.Date(format(Sys.Date(), "%Y-%m-01")),
      by = "-1 month",
      length.out = 2
    )[2],
    "%Y-%m"
  )
  resolve_target_month(month = prev_month, mode = "explicit")
}
message(sprintf("Starting monthly GDX pipeline for month: %s", target_month))

# Resolve S3 source selection for this run.
# Priority:
# 1) explicit BCSTATS_S3_SOURCE_SUBFOLDER / BCSTATS_S3_KEY_PATTERN, else
# 2) the documented mapping in resolve_s3_selection().
bucket <- Sys.getenv("BCSTATS_S3_BUCKET", unset = "")
prefix <- Sys.getenv("BCSTATS_S3_PREFIX", unset = "")
region <- Sys.getenv("AWS_DEFAULT_REGION", unset = "")

if (!nzchar(bucket) || !nzchar(prefix) || !nzchar(region)) {
  stop(
    "Missing S3 environment configuration for monthly pipeline.",
    call. = FALSE
  )
}

clean_env <- function(name) {
  val <- Sys.getenv(name, unset = "")
  if (nzchar(val)) str_remove(str_remove(val, "^/"), "/$") else ""
}

source_subfolder_env <- clean_env("BCSTATS_S3_SOURCE_SUBFOLDER")
key_pattern_env <- Sys.getenv("BCSTATS_S3_KEY_PATTERN", unset = "")

if (nzchar(source_subfolder_env) || nzchar(key_pattern_env)) {
  selection <- list(
    subfolder = source_subfolder_env,
    key_pattern = key_pattern_env,
    rule = "explicit environment override"
  )
} else {
  selection <- resolve_s3_selection(target_month)
}

message(sprintf("S3 selection rule: %s", selection$rule))
if (nzchar(selection$subfolder)) {
  message(sprintf("  subfolder:   %s", selection$subfolder))
}
if (nzchar(selection$key_pattern)) {
  message(sprintf("  key pattern: %s", selection$key_pattern))
}

# Pre-flight: confirm the selection resolves to exactly one file per report
# family before downloading. Guards against a rerun in the same generation
# month producing two complete sets with different timestamps, which the
# downloader's basename check cannot detect.
objects_now <- get_bucket(
  bucket = bucket,
  prefix = prefix,
  region = region,
  max = Inf
)

selected <- tibble(
  key = vapply(objects_now, function(x) as.character(x$Key), character(1)),
  size = vapply(objects_now, function(x) as.numeric(x$Size), numeric(1))
) |>
  filter(
    !is.na(key),
    size > 0,
    str_starts(key, prefix),
    str_detect(key, "\\.csv$")
  ) |>
  mutate(
    key_rel = str_remove(str_remove(key, paste0("^", fixed(prefix))), "^/")
  )

if (nzchar(selection$subfolder)) {
  selected <- selected |>
    filter(str_starts(key_rel, paste0(selection$subfolder, "/")))
}
if (nzchar(selection$key_pattern)) {
  selected <- selected |> filter(str_detect(key_rel, selection$key_pattern))
}

if (nrow(selected) == 0) {
  stop(
    sprintf(
      "No S3 files matched the selection for %s. Upstream files may not be published yet.",
      target_month
    ),
    call. = FALSE
  )
}

# One logical report per site/report family, ignoring timestamp and part number.
duplicate_reports <- selected |>
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
  nrow(selected),
  target_month
))

# Ensure downstream scripts use one consistent month and selection.
Sys.setenv(GDX_TARGET_MONTH = target_month)
Sys.setenv(BCSTATS_S3_SOURCE_SUBFOLDER = selection$subfolder)
Sys.setenv(BCSTATS_S3_KEY_PATTERN = selection$key_pattern)

message("Step 1/3: Download raw GDX monthly CSVs...")
source("R/gdx-01-fetch-s3.R")

message("Step 2/3: Analyze and write monthly summary tables...")
source("R/gdx-02-analyze.R")

message("Step 3/3: Render dashboard...")

# Name the artifact by reporting month, e.g. gdx_web_dashboard_May-2026.html.
# quarto_render() writes output_file into the .qmd's own directory.
dashboard_qmd <- "Report/gdx_web_dashboard.qmd"
dashboard_file <- sprintf(
  "gdx_web_dashboard_%s.html",
  format(as.Date(paste0(target_month, "-01")), "%B-%Y")
)

# Cap the dashboard at the reporting month so the artifact matches its filename.
Sys.setenv(GDX_DASHBOARD_MAX_MONTH = target_month)

quarto::quarto_render(
  dashboard_qmd,
  output_file = dashboard_file
)

dashboard_path <- file.path(dirname(dashboard_qmd), dashboard_file)
if (!file.exists(dashboard_path)) {
  stop(
    sprintf("Expected dashboard output not found: %s", dashboard_path),
    call. = FALSE
  )
}

# Post-render sanity checks
output_dir <- file.path(OUTPUT_TABLES, "cms_lite", target_month)
if (!dir.exists(output_dir)) {
  stop(
    sprintf("Expected output month directory not found: %s", output_dir),
    call. = FALSE
  )
}
assert_monthly_outputs(output_dir)

message("Monthly GDX pipeline complete.")
message(sprintf("Month: %s", target_month))
message(sprintf("Source selection: %s", selection$rule))
message(sprintf("Monthly tables: %s", output_dir))
message("Dashboard output: ", dashboard_path)
