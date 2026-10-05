# Monthly GDX Dashboard Runbook

## Purpose

Run the GDX web dashboard monthly pipeline for the previous month (default), or rerun/backfill a specific month.

## Prerequisites

- VPN/LAN access to the project working paths used by `R/00-setup.R`
- Required AWS/S3 environment variables are set for the GDX download step
- The local project environment is configured for the R scripts in this repo
- R packages are installed as handled by `R/00-setup.R`

Note: the GDX monthly pipeline relies on the AWS/S3 environment variables for the data pull. The GA and shinyapps settings are still part of the shared project setup in `R/00-setup.R`, but they are not the primary requirement for the GDX report refresh itself.

## Normal Monthly Run (previous month)

In R console:

```r
# Recommended: pin to one upstream drop folder to avoid collisions.
Sys.setenv(BCSTATS_S3_SOURCE_SUBFOLDER = "UAT_20260720")
source("R/gdx-run-monthly-pipeline.R")
```

This will:
1. Resolve the target month as the previous calendar month.
2. Download the selected source-data exports into the LAN/local working data directory for that month.
3. Analyze the data and write the monthly summary tables to the LAN/local working output directory.
4. Render the dashboard defined in `Report/gdx_web_dashboard.qmd`.

The example above is historical and should only be used for a specific known delivery structure. For routine monthly runs, the pipeline normally resolves the correct upstream selection automatically using the month mapping rules in `R/functions/month-run-helpers.R`.

## Backfill or Rerun a Specific Month

In R console:

```r
Sys.setenv(GDX_TARGET_MONTH = "2026-05")
source("R/gdx-run-monthly-pipeline.R")
```

This forces a specific reporting month instead of using the default previous-month behavior.

## Expected Outputs

- Raw data files: LAN/local working data directory for the reporting month
- Monthly summary tables: LAN/local working output directory for that month
- Dashboard HTML: rendered file in the working report output location, often named with the reporting month (for example, `gdx_web_dashboard_May-2026.html`)

## Built-in Validation

The pipeline fails early when:
- expected monthly report families are missing in raw input,
- duplicate basenames are detected in selected S3 files (to prevent silent overwrite),
- required monthly output tables are missing or empty,
- the render step fails.

Govstats-only tables (`asset/search/google`) are checked and warn if absent or empty.

## Common Issues

- **Missing AWS/S3 environment variables**: define the required S3 variables and retry.
- **Input directory missing**: verify the monthly download step completed for the target month.
- **Missing report family**: check upstream GDX export availability for that site/report.
- **Render failure**: open `Report/gdx_web_dashboard.qmd` and run render directly to inspect errors.
- **Multiple upstream selections**: narrow the source selection with `BCSTATS_S3_SOURCE_SUBFOLDER` or `BCSTATS_S3_KEY_PATTERN` so only one delivery set is ingested.
