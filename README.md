<!-- badges: start -->

[![Lifecycle:Experimental](https://img.shields.io/badge/Lifecycle-Experimental-339999)](https://github.com/bcgov/repomountie/blob/master/doc/lifecycle-badges.md) [![License:Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/license/apache-2-0/)

<!-- badges: end -->

## Project Description

R code to fetch, summarize, and publish web analytics for BC Stats dashboards hosted on Shiny and monitored through Google Analytics 4.

This repository contains **code only**. Raw data, derived tables, visuals, and rendered reports are written to secure LAN storage accessed through [`safepaths`](https://github.com/bcgov/safepaths).

## What the project does

The current pipeline:

- downloads raw GA4 usage data by day and ISO week
- downloads shinyapps.io concurrency metrics
- builds summary tables for usage, geography, technology, and downloads
- creates executive-summary visuals and tables
- renders a Quarto dashboard
- archives the rendered dashboard HTML to the production reports folder

## Repository workflow

The main scripts are:

- `R/00-setup.R`\
  Loads packages, configures LAN paths, reads environment variables, authenticates to GA4 and shinyapps.io.

- `R/apps-01-fetch-ga-history.R`\
  Full GA4 pull. Downloads and caches raw daily, weekly, geo, tech, and download-event data as `.rds` files.

- `R/apps-03-fetch-shinyapps.R`\
  Downloads shinyapps.io concurrency metrics for the maintained apps and saves them as `shinyapps_concurrency.rds`.

- `R/apps-02-fetch-ga-weekly.R`\
  Incremental weekly GA4 updater. Appends only new raw records and overwrites the cached `.rds` files.

- `R/02-analyze-usage.R`\
  Filters to the maintained dashboards and writes summary CSVs, including:

  - `usage_summary.csv`
  - `location_summary.csv`
  - `tech_summary.csv`
  - `device_summary.csv`
  - `os_summary.csv`
  - `browser_summary.csv`
  - `download_summary.csv`
  - `usage_comparison.csv`
  - `weekly_usage.csv`
  - `visits_minmax_summary.csv`

- `R/03-analyze-concurrency.R`\
  Summarizes concurrency metrics for shinyapps.io apps.

- `R/apps-06-executive-summary.R`\
  Produces executive-summary CSV output and PNG visuals in `outputs/visuals/`.

- `R/apps-run-weekly-pipeline.R`\
  Master weekly pipeline. Runs the incremental GA4 refresh, rebuilds summaries, renders `Report/dashboard.qmd`, and archives the HTML file into `outputs/reports/` with a week-based filename.

- `Report/dashboard.qmd`\
  Quarto dashboard that reads the generated CSV and RDS outputs and renders the reporting interface.

## Dashboards currently tracked

The usage analysis currently reports on these dashboards:

- LAEP
- Student Outcomes
- popApp
- BC Small Business
- LFS app
- Economic-Indicators
- BCDS-DIP Linkage Rates
- Household Projections
- Country Trade Profiles
- Interprovincial Migration
- BC Retail Sales

## Prerequisites

- **R**: 4.0.0+
- **VPN / network access**: required to reach the secure LAN path
- **GA4 access**: service account email and JSON key file
- **shinyapps.io access**: account name, token, and secret
- **safepaths configuration**: required to resolve the LAN root folder
- **Quarto**: required to render the dashboard

## Secure access and credentials

Secrets must never be committed.

Use a local-only configuration such as `~/.Renviron` or a separate file referenced by `EXTRA_RENVIRON_PATH`.

### Required environment variables

``` text
SAFEPATHS_NETWORK_PATH
GA_SERVICE_EMAIL
GA_SERVICE_KEY
SHINY_ACC_NAME
SHINY_TOKEN
SHINY_SECRET
```

### Optional environment variables

``` text
GA_PROPERTY_ID
GA_DATE_START
GA_DATE_END
EXTRA_RENVIRON_PATH
```

### Defaults used in code

If optional values are not set, the scripts currently default to:

- `GA_DATE_START = 2024-01-01`
- `GA_DATE_END = Sys.Date() - 1`
- `R/gdx-01-fetch-s3.R` uses an in-script `uat_month` value (set in the script and updated monthly).
- `R/gdx-02-analyze.R` uses an in-script `analysis_month` value (set in the script and updated monthly); set `analysis_month <- NA_character_` to include all month folders under `data/cms_lite` recursively.

`GA_SERVICE_KEY` must point to an existing GA service-account JSON file.

## Data sources

- **Google Analytics 4 API** via `googleAnalyticsR`
- **shinyapps.io metrics API** via `rsconnect::showMetrics()`

## LAN storage structure

All raw data and outputs are written under:

``` text
{LAN_FOLDER}/0. Misc/Data Science Tooling/web-hosting-and-dashboards/shinyapps_webtraffic_monitoring/
├── data/
│   ├── daily_usage_raw.rds
│   ├── weekly_usage_raw.rds
│   ├── geo_data_raw.rds
│   ├── tech_data_raw.rds
│   ├── download_data_raw.rds
│   └── shinyapps_concurrency.rds
└── outputs/
    ├── reports/
    ├── tables/
    └── visuals/
```

## Installation

Install the packages used by the current scripts:

``` r
install.packages(c(
  "googleAnalyticsR",
  "tidyverse",
  "lubridate",
  "zoo",
  "janitor",
  "slider",
  "rsconnect",
  "glue",
  "ggplot2",
  "forcats",
  "quarto",
  "flexdashboard",
  "plotly",
  "DT",
  "scales",
  "knitr"
))

remotes::install_github("bcgov/safepaths")
```

## Typical usage

### One-time or full refresh

Run the raw-data collection and analysis scripts in sequence:

``` r
source("R/apps-01-fetch-ga-history.R")
source("R/apps-03-fetch-shinyapps.R")
source("R/02-analyze-usage.R")
source("R/03-analyze-concurrency.R")
source("R/apps-06-executive-summary.R")
quarto::quarto_render("Report/dashboard.qmd")
```

### Weekly production update

Run the master pipeline:

``` r
source("R/apps-run-weekly-pipeline.R")
```

This script:

1.  refreshes GA4 raw data incrementally
2.  rebuilds summary tables
3.  renders `Report/dashboard.qmd`
4.  copies the rendered HTML into `outputs/reports/`
5.  names the archived report as `Traffic_Snapshot_Week_Of_YYYY-MM-DD.html`

## Outputs

Typical outputs include:

### Tables

- weekly usage summaries
- recent week and recent month comparison metrics
- rolling averages
- geography summaries
- device, operating system, and browser summaries
- file download summaries
- app comparison rankings
- visit/time/download summary tables
- concurrency summaries

### Visuals

Generated by `R/apps-06-executive-summary.R`:

- `visits_trend_plot.png`
- `visits_trend_faceted_plot.png`
- `visits_minmax_plot.png`
- `visits_minmax_plot_high.png`
- `visits_minmax_plot_low.png`
- `max_concurrent_plot.png`

### Rendered report

- `Report/dashboard.html` during render
- archived HTML report in `outputs/reports/`

## Notes for code review and development

- This repository stores only code; do not commit LAN data or credentials.
- `R/apps-02-fetch-ga-weekly.R` assumes the raw `.rds` cache files already exist.
- The Quarto dashboard reads generated files from LAN storage, not from the repository itself.
- The dashboard can be rendered directly with:

``` r
quarto::quarto_render("Report/dashboard.qmd")
```

## Guiding principles

1.  This GitHub repository stores only code.
2.  Data and outputs reside on secure LAN storage.
3.  Credentials are supplied locally and must not be committed.
4.  The analysis is intended to support transparent, reproducible reporting for dashboard usage.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md).

This project follows the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).

## Contact

For access questions or the `safepaths` configuration key, contact:

- Zhijia Ju: https://github.com/Anakin2009
- Or open an issue in this repository

## License

Copyright 2026 Province of British Columbia

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.