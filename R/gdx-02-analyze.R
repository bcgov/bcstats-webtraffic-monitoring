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

# Purpose: Analyze reports by site (in-memory only).

# Keep this so the analysis step can also be sourced independently of the pipeline.
source("R/00-setup.R")

# The monthly pipeline supplies target_month; resolve it only for standalone runs.
if (!exists("target_month", inherits = FALSE)) {
  target_month <- resolve_target_month(mode = "previous")
}

target_dir <- file.path(DATA_RAW, "cms_lite", target_month)

if (!dir.exists(target_dir)) {
  stop(
    sprintf("Analysis input directory does not exist: %s", target_dir),
    call. = FALSE
  )
}

# Ensure expected monthly source report families exist before analysis.
assert_cmslite_reports_present(target_dir)

# Create CMS Lite output subfolder for this analysis month, if not already made.
cmslite_output_dir <- file.path(OUTPUT_TABLES, "cms_lite", target_month)
dir.create(cmslite_output_dir, recursive = TRUE, showWarnings = FALSE)

# Load the five shared report families for each site and three extras for govstats.
reports_by_site <- list(
  outcomes = base_reports,
  antiracism = base_reports,
  govstats = c(base_reports, extra_reports)
)
reports <- imap(reports_by_site, \(types, site) {
  map(types, \(type) load_report(target_dir, site, type)) |>
    rlang::set_names(types)
})

govstats_click <- reports$govstats$click

##### ============================================================
##### VALIDATE REPORTING PERIOD
##### Filenames carry a generation timestamp, not the reporting month
##### (see docs/BC_STATS_S3_FILE_GUIDE.md), so the month is confirmed from
##### file contents before any analysis runs.
##### ============================================================

assert_reports_month(
  imap(reports, \(site_reports, site) {
    rlang::set_names(site_reports, paste(site, names(site_reports)))
  }) |>
    flatten(),
  target_month
)

message(sprintf(
  "Month %s: reporting-period checks completed for %s source reports (review any warnings above).",
  target_month,
  sum(lengths(reports))
))

analyzers <- list(
  pageview = analyze_pageview,
  click = analyze_click,
  referurl = analyze_referurl,
  platform = analyze_platform,
  geoloc = analyze_geoloc,
  asset = analyze_asset,
  search = analyze_search,
  google = analyze_google
)

##### ============================================================
##### FINAL OBJECT (in-memory nested list, for inspection)
##### ============================================================

cmslite_analysis <- map(reports, \(site_reports) {
  imap(site_reports, \(report, type) analyzers[[type]](report))
})

##### ============================================================
##### DASHBOARD PREP: tidy combined tables (one row-bound table
##### per metric, tagged with a `site` column)
##### ============================================================

cmslite_tables <- list(
  cmslite_daily = combine_sites(
    cmslite_analysis,
    c("pageview", "daily")
  ),
  cmslite_top_pages = combine_sites(
    cmslite_analysis,
    c("pageview", "top_pages")
  ),
  cmslite_clicks_daily = combine_sites(
    cmslite_analysis,
    c("click", "daily")
  ),
  cmslite_top_targets = combine_sites(
    cmslite_analysis,
    c("click", "top_targets")
  ),
  cmslite_top_referrers = combine_sites(
    cmslite_analysis,
    c("referurl", "top_referrers")
  ),
  cmslite_by_os = combine_sites(
    cmslite_analysis,
    c("platform", "by_os")
  ),
  cmslite_by_geo = combine_sites(
    cmslite_analysis,
    c("geoloc", "by_geo")
  ),
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
##### Saved to OUTPUT_TABLES/cms_lite/<target_month>/ with month-tagged filenames.
##### Comment out the loop below to avoid overwriting CSVs during development.
##### ============================================================

imap(cmslite_tables, \(x, name) {
  if (!is.null(x) && nrow(x) > 0) {
    filename <- sprintf("%s_%s.csv", name, target_month)
    write_csv(x, file = file.path(cmslite_output_dir, filename))
  }
})

# Validate output table completeness before dashboard render.
assert_monthly_outputs(cmslite_output_dir)

message(sprintf(
  "Month %s: wrote CMS Lite output tables to: %s",
  target_month,
  cmslite_output_dir
))

cmslite_analysis
