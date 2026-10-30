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

# CMS Lite analysis helper functions
# These functions use dplyr, purrr, readr, stringr, janitor, and rlang.

# Metric Definitions
# Impressions: The total number of times your ad or link was displayed on a screen.
# Clicks: The total number of times users actually clicked on the displayed link or ad.
# CTR: The ratio showing how often an impression results in a click.

# Map canonical names to all known CMS Lite source column variants.
cmslite_name_map <- list(
  date = c(
    "page_views_page_view_start_date",
    "clicks_click_time_date",
    "asset_downloads_download_time_date",
    "searches_search_date",
    "searches_search_time_date",
    "google_search_date",
    "google_search_month"
  ),
  page_views = c("page_views_page_view_count"),
  sessions = c("page_views_session_count"),
  users = c("page_views_user_count"),
  page_url = c("page_views_page_display_url"),
  referrer_url = c("page_views_page_referrer_display_url"),
  os = c("page_views_os_family"),
  country_code = c("page_views_geo_country"),
  country = c("page_views_geo_country_name"),
  region_code = c("page_views_geo_region"),
  region = c(
    "page_views_geo_region_name",
    "page_views_geo_region_or_country",
    "page_views_geo_region"
  ),
  click_count = c(
    "clicks_click_count",
    "google_search_total_clicks",
    "google_search_click_count"
  ),
  target_url = c("clicks_target_display_url"),
  asset_file = c("asset_downloads_asset_file"),
  asset_url = c("asset_downloads_asset_display_url"),
  asset_theme_id = c("asset_themes_node_id"),
  downloads = c("asset_downloads_count"),
  search_term = c("searches_search_terms"),
  searches = c(
    "searches_row_count",
    "searches_search_count",
    "searches_count"
  ),
  query = c("google_search_query"),
  page = c("google_search_page"),
  impressions = c(
    "google_search_total_impressions",
    "google_search_impressions"
  )
)

# Merge source columns `aliases` in priority order into canonical `output`.
# Input: data frame, character alias names, and one output name.
# Returns the data frame unchanged if no alias exists; otherwise renames or
# coalesces aliases. Used by normalize_cmslite_names().
coalesce_aliases <- function(df, aliases, output) {
  present <- aliases[aliases %in% names(df)]
  if (length(present) == 0) {
    return(df)
  }

  if (length(present) == 1) {
    return(dplyr::rename(df, !!output := dplyr::all_of(present)))
  }

  dplyr::mutate(df, !!output := dplyr::coalesce(!!!rlang::syms(present))) |>
    dplyr::select(-dplyr::any_of(setdiff(present, output)))
}

# Rename/coalesce known source fields using cmslite_name_map.
# Input: a cleaned CMS Lite data frame. Returns a data frame with canonical
# names; depends on coalesce_aliases().
normalize_cmslite_names <- function(df) {
  purrr::reduce(
    .x = names(cmslite_name_map),
    .f = \(acc, nm) coalesce_aliases(acc, cmslite_name_map[[nm]], nm),
    .init = df
  )
}

# Load and normalize CSV parts for one site and report family.
# Inputs: raw_dir (search root), site and report (filename components).
# Returns a row-bound data frame with numeric metrics and source_file;
# errors when no files match. Depends on normalize_cmslite_names().
load_report <- function(raw_dir, site, report) {
  all_csv <- list.files(
    raw_dir,
    pattern = "\\.csv$",
    recursive = TRUE,
    full.names = TRUE
  )

  report_pattern <- paste0("webdata_bcstats_", site, "_", report, "_monthly")
  matched <- all_csv[stringr::str_detect(basename(all_csv), report_pattern)]

  if (length(matched) == 0) {
    stop(
      sprintf("No files found for site='%s', report='%s'.", site, report),
      call. = FALSE
    )
  }

  purrr::map(
    matched,
    \(f) {
      readr::read_csv(
        f,
        show_col_types = FALSE,
        col_types = readr::cols(.default = readr::col_guess())
      ) |>
        janitor::clean_names(case = "snake") |>
        normalize_cmslite_names() |>
        dplyr::mutate(
          dplyr::across(
            dplyr::any_of(c(
              "click_count",
              "impressions",
              "downloads",
              "searches",
              "page_views",
              "sessions",
              "users"
            )),
            ~ suppressWarnings(readr::parse_number(as.character(.x)))
          )
        ) |>
        dplyr::mutate(source_file = basename(f))
    }
  ) |>
    purrr::list_rbind()
}

# Summarize normalized page views, sessions and users by date and page URL.
# Input: load_report() data with date, page_url and those three metrics.
# Returns a list of daily and top_pages tables.
analyze_pageview <- function(df) {
  list(
    daily = df |>
      dplyr::summarise(
        page_views = sum(page_views, na.rm = TRUE),
        sessions = sum(sessions, na.rm = TRUE),
        users = sum(users, na.rm = TRUE),
        .by = date
      ) |>
      dplyr::arrange(date),
    top_pages = df |>
      dplyr::summarise(
        page_views = sum(page_views, na.rm = TRUE),
        sessions = sum(sessions, na.rm = TRUE),
        users = sum(users, na.rm = TRUE),
        .by = page_url
      ) |>
      dplyr::arrange(dplyr::desc(page_views))
  )
}

# Summarize normalized clicks by date and target URL.
# Input: load_report() data with date, target_url and click_count.
# Returns a list of daily and top_targets tables.
analyze_click <- function(df) {
  list(
    daily = df |>
      dplyr::summarise(
        clicks = sum(click_count, na.rm = TRUE),
        .by = date
      ) |>
      dplyr::arrange(date),
    top_targets = df |>
      dplyr::summarise(
        clicks = sum(click_count, na.rm = TRUE),
        .by = target_url
      ) |>
      dplyr::arrange(dplyr::desc(clicks))
  )
}

# Summarize normalized page views by referrer URL.
# Input: load_report() data with referrer_url and page_views.
# Returns a list containing the top_referrers table.
analyze_referurl <- function(df) {
  list(
    top_referrers = df |>
      dplyr::summarise(
        page_views = sum(page_views, na.rm = TRUE),
        .by = referrer_url
      ) |>
      dplyr::arrange(dplyr::desc(page_views))
  )
}

# Summarize normalized page views, sessions and users by operating system.
# Input: load_report() data with os and those three metrics.
# Returns a list containing the by_os table.
analyze_platform <- function(df) {
  list(
    by_os = df |>
      dplyr::summarise(
        page_views = sum(page_views, na.rm = TRUE),
        sessions = sum(sessions, na.rm = TRUE),
        users = sum(users, na.rm = TRUE),
        .by = os
      ) |>
      dplyr::arrange(dplyr::desc(page_views))
  )
}

# Summarize normalized traffic by available country and/or region fields.
# Input: load_report() data with at least one of country/region and the
# page_views, sessions and users metrics. Returns a list with by_geo;
# errors if neither geographic field exists.
analyze_geoloc <- function(df) {
  group_vars <- intersect(c("country", "region"), names(df))

  if (length(group_vars) == 0) {
    stop(
      "Geolocation report is missing both 'country' and 'region' columns.",
      call. = FALSE
    )
  }

  list(
    by_geo = df |>
      dplyr::summarise(
        page_views = sum(page_views, na.rm = TRUE),
        sessions = sum(sessions, na.rm = TRUE),
        users = sum(users, na.rm = TRUE),
        .by = dplyr::all_of(group_vars)
      ) |>
      dplyr::arrange(dplyr::desc(page_views))
  )
}

# Summarize normalized asset downloads by date and asset identity.
# Input: load_report() data with date, asset_file, asset_url and downloads.
# Returns a list of daily and top_assets tables.
analyze_asset <- function(df) {
  list(
    daily = df |>
      dplyr::summarise(
        downloads = sum(downloads, na.rm = TRUE),
        .by = date
      ) |>
      dplyr::arrange(date),
    top_assets = df |>
      dplyr::summarise(
        downloads = sum(downloads, na.rm = TRUE),
        .by = c(asset_file, asset_url)
      ) |>
      dplyr::arrange(dplyr::desc(downloads))
  )
}

# Summarize normalized on-site searches by search term.
# Input: load_report() data with search_term and searches.
# Returns a list containing the top_terms table.
analyze_search <- function(df) {
  list(
    top_terms = df |>
      dplyr::summarise(
        searches = sum(searches, na.rm = TRUE),
        .by = search_term
      ) |>
      dplyr::arrange(dplyr::desc(searches))
  )
}

# Summarize Google search clicks/impressions and calculate CTR by query/page.
# Input: load_report() data with query, page, click_count and impressions.
# Returns a list containing the top_queries table (CTR is NA for zero impressions).
analyze_google <- function(df) {
  list(
    top_queries = df |>
      dplyr::mutate(
        dplyr::across(
          c(click_count, impressions),
          ~ readr::parse_number(as.character(.x))
        )
      ) |>
      dplyr::summarise(
        clicks = sum(click_count, na.rm = TRUE),
        impressions = sum(impressions, na.rm = TRUE),
        .by = c(query, page)
      ) |>
      dplyr::mutate(
        ctr = dplyr::if_else(impressions > 0, clicks / impressions, NA_real_)
      ) |>
      dplyr::arrange(dplyr::desc(clicks))
  )
}

# Extract a nested analysis table for each site and add its site label.
# Inputs: named analysis list and character path within each site's results.
# Returns row-bound tables with a site column; missing paths are skipped.
combine_sites <- function(analysis, path) {
  purrr::imap(analysis, \(site_analysis, site) {
    tbl <- purrr::pluck(site_analysis, !!!path)
    if (is.null(tbl)) {
      return(NULL)
    }
    dplyr::mutate(tbl, site = site, .before = 1)
  }) |>
    purrr::list_rbind()
}

# Rank BC Data Catalogue target URLs by click count.
# Inputs: load_report() click data with target_url/click_count and a row limit.
# Returns a ranked URL-level data frame of at most top_n rows.
analyze_bcdc_click <- function(df, top_n = 20) {
  df |>
    dplyr::filter(
      stringr::str_detect(
        target_url,
        stringr::regex("catalogue\\.data\\.gov\\.bc\\.ca", ignore_case = TRUE)
      )
    ) |>
    dplyr::summarise(
      clicks = sum(click_count, na.rm = TRUE),
      .by = target_url
    ) |>
    dplyr::arrange(dplyr::desc(clicks)) |>
    dplyr::slice(1:top_n) |>
    dplyr::mutate(rank = dplyr::row_number(), .before = target_url)
}

# Summarize BC Data Catalogue asset downloads by file and URL.
# Input: load_report() asset data with asset_file, asset_url and downloads.
# Returns a downloads-ranked data frame.
analyze_bcdc_asset <- function(df) {
  df |>
    dplyr::filter(
      stringr::str_detect(
        asset_url,
        stringr::regex("catalogue\\.data\\.gov\\.bc\\.ca", ignore_case = TRUE)
      )
    ) |>
    dplyr::summarise(
      downloads = sum(downloads, na.rm = TRUE),
      .by = c(asset_file, asset_url)
    ) |>
    dplyr::arrange(dplyr::desc(downloads))
}
