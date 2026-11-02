# One-click monthly pipeline for GDX web dashboard
# Default behavior: process previous calendar month.
# Optional explicit month override: Sys.setenv(GDX_TARGET_MONTH = "YYYY-MM")

source("R/00-setup.R")

library(dplyr)
library(stringr)

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
s3_config <- get_s3_config()
bucket <- s3_config$bucket
prefix <- s3_config$prefix
region <- s3_config$region

use_explicit_s3_selection <- tolower(Sys.getenv(
  "GDX_USE_EXPLICIT_S3_SELECTION",
  unset = "false"
)) %in%
  c("true", "1", "yes")

source_subfolder_env <- if (use_explicit_s3_selection) {
  str_remove(
    str_remove(Sys.getenv("BCSTATS_S3_SOURCE_SUBFOLDER", unset = ""), "^/"),
    "/$"
  )
} else {
  ""
}

key_pattern_env <- if (use_explicit_s3_selection) {
  Sys.getenv("BCSTATS_S3_KEY_PATTERN", unset = "")
} else {
  ""
}

if (
  use_explicit_s3_selection &&
    (nzchar(source_subfolder_env) || nzchar(key_pattern_env))
) {
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

quarto_render(
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
