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

# Purpose: Analyze CMS Lite reports by site (in-memory only).

source("R/00-setup.R")
source("R/functions/month-run-helpers.R")

library(dplyr)
library(readr)
library(stringr)
library(purrr)

# Resolve target month (default: previous month).
# Override with env var GDX_TARGET_MONTH=YYYY-MM when needed.
analysis_month <- resolve_target_month(mode = "previous")

raw_dir <- file.path(DATA_RAW, "cms_lite", analysis_month)

if (!dir.exists(raw_dir)) {
  stop(
    sprintf("Analysis input directory does not exist: %s", raw_dir),
    call. = FALSE
  )
}

# Ensure expected monthly source report families exist before analysis.
assert_cmslite_reports_present(raw_dir)

# Create CMS Lite output subfolder for this analysis month.
cmslite_output_dir <- file.path(OUTPUT_TABLES, "cms_lite", analysis_month)
dir.create(cmslite_output_dir, recursive = TRUE, showWarnings = FALSE)

# Shared helper functions
source("R/functions/gdx-web-analysis-functions.R")

##### ============================================================
##### PART 1: outcomes.bcstats.gov.bc.ca (5 reports)
##### ============================================================

outcomes_pageview <- load_report(raw_dir, "outcomes", "pageview")
outcomes_click <- load_report(raw_dir, "outcomes", "click")
outcomes_referurl <- load_report(raw_dir, "outcomes", "referurl")
outcomes_platform <- load_report(raw_dir, "outcomes", "platform")
outcomes_geoloc <- load_report(raw_dir, "outcomes", "geoloc")


outcomes_analysis <- list(
  pageview = analyze_pageview(outcomes_pageview),
  click = analyze_click(outcomes_click),
  referurl = analyze_referurl(outcomes_referurl),
  platform = analyze_platform(outcomes_platform),
  geoloc = analyze_geoloc(outcomes_geoloc)
)

##### ============================================================
##### PART 2: antiracism.gov.bc.ca (5 reports)
##### ============================================================

antiracism_pageview <- load_report(raw_dir, "antiracism", "pageview")
antiracism_click <- load_report(raw_dir, "antiracism", "click")
antiracism_referurl <- load_report(raw_dir, "antiracism", "referurl")
antiracism_platform <- load_report(raw_dir, "antiracism", "platform")
antiracism_geoloc <- load_report(raw_dir, "antiracism", "geoloc")


antiracism_analysis <- list(
  pageview = analyze_pageview(antiracism_pageview),
  click = analyze_click(antiracism_click),
  referurl = analyze_referurl(antiracism_referurl),
  platform = analyze_platform(antiracism_platform),
  geoloc = analyze_geoloc(antiracism_geoloc)
)

##### ============================================================
##### PART 3: www2.gov.bc.ca/gov/content/data/statistics (8 reports)
##### ============================================================

govstats_pageview <- load_report(raw_dir, "govstats", "pageview")
govstats_click <- load_report(raw_dir, "govstats", "click")
govstats_referurl <- load_report(raw_dir, "govstats", "referurl")
govstats_platform <- load_report(raw_dir, "govstats", "platform")
govstats_geoloc <- load_report(raw_dir, "govstats", "geoloc")
govstats_asset <- load_report(raw_dir, "govstats", "asset")
govstats_search <- load_report(raw_dir, "govstats", "search")
govstats_google <- load_report(raw_dir, "govstats", "google")

##### ============================================================
##### VALIDATE REPORTING PERIOD
##### Filenames carry a generation timestamp, not the reporting month
##### (see docs/BC_STATS_S3_FILE_GUIDE.md), so the month is confirmed from
##### file contents before any analysis runs.
##### ============================================================

assert_reports_month(
  list(
    "outcomes pageview" = outcomes_pageview,
    "outcomes click" = outcomes_click,
    "outcomes referurl" = outcomes_referurl,
    "outcomes platform" = outcomes_platform,
    "outcomes geoloc" = outcomes_geoloc,
    "antiracism pageview" = antiracism_pageview,
    "antiracism click" = antiracism_click,
    "antiracism referurl" = antiracism_referurl,
    "antiracism platform" = antiracism_platform,
    "antiracism geoloc" = antiracism_geoloc,
    "govstats pageview" = govstats_pageview,
    "govstats click" = govstats_click,
    "govstats referurl" = govstats_referurl,
    "govstats platform" = govstats_platform,
    "govstats geoloc" = govstats_geoloc,
    "govstats asset" = govstats_asset,
    "govstats search" = govstats_search,
    "govstats google" = govstats_google
  ),
  analysis_month
)

message(sprintf("Month %s: all 18 source reports validated.", analysis_month))

govstats_analysis <- list(
  pageview = analyze_pageview(govstats_pageview),
  click = analyze_click(govstats_click),
  referurl = analyze_referurl(govstats_referurl),
  platform = analyze_platform(govstats_platform),
  geoloc = analyze_geoloc(govstats_geoloc),
  asset = analyze_asset(govstats_asset),
  search = analyze_search(govstats_search),
  google = analyze_google(govstats_google)
)

##### ============================================================
##### FINAL OBJECT (in-memory nested list, for inspection)
##### ============================================================

cmslite_analysis <- list(
  outcomes = outcomes_analysis,
  antiracism = antiracism_analysis,
  govstats = govstats_analysis
)

##### ============================================================
##### DASHBOARD PREP: tidy combined tables (one row-bound table
##### per metric, tagged with a `site` column)
##### ============================================================

# Pull a nested table (e.g. c("pageview", "daily")) from each site's analysis,
# add a `site` column, and row-bind. Sites lacking that path are skipped, so
# govstats-only reports (asset/search/google) bind cleanly.
combine_sites <- function(analysis, path) {
  imap(analysis, \(site_analysis, site) {
    tbl <- purrr::pluck(site_analysis, !!!path)
    if (is.null(tbl)) {
      return(NULL)
    }
    mutate(tbl, site = site, .before = 1)
  }) |>
    list_rbind()
}

cmslite_tables <- list(
  cmslite_daily = combine_sites(cmslite_analysis, c("pageview", "daily")),
  cmslite_top_pages = combine_sites(
    cmslite_analysis,
    c("pageview", "top_pages")
  ),
  cmslite_clicks_daily = combine_sites(cmslite_analysis, c("click", "daily")),
  cmslite_top_targets = combine_sites(
    cmslite_analysis,
    c("click", "top_targets")
  ),
  cmslite_top_referrers = combine_sites(
    cmslite_analysis,
    c("referurl", "top_referrers")
  ),
  cmslite_by_os = combine_sites(cmslite_analysis, c("platform", "by_os")),
  cmslite_by_geo = combine_sites(cmslite_analysis, c("geoloc", "by_geo")),
  cmslite_asset_downloads_daily = combine_sites(
    cmslite_analysis,
    c("asset", "daily")
  ),
  cmslite_top_assets = combine_sites(
    cmslite_analysis,
    c("asset", "top_assets")
  ),
  cmslite_search_terms = combine_sites(
    cmslite_analysis,
    c("search", "top_terms")
  ),
  cmslite_google_queries = combine_sites(
    cmslite_analysis,
    c("google", "top_queries")
  )
)

##### ============================================================
##### WRITE DASHBOARD CSVs
##### Saved to OUTPUT_TABLES/cms_lite/<analysis_month>/ with month-tagged filenames.
##### Comment out the loop below to avoid overwriting CSVs during development.
##### ============================================================

imap(cmslite_tables, \(x, name) {
  if (!is.null(x) && nrow(x) > 0) {
    filename <- sprintf("%s_%s.csv", name, analysis_month)
    write_csv(x, file = file.path(cmslite_output_dir, filename))
  }
})

# Validate output table completeness before dashboard render.
assert_monthly_outputs(cmslite_output_dir)

message(sprintf(
  "Month %s: wrote CMS Lite output tables to: %s",
  analysis_month,
  cmslite_output_dir
))

cmslite_analysis
