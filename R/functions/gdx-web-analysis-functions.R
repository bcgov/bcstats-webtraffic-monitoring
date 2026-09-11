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

normalize_cmslite_names <- function(df) {
  purrr::reduce(
    .x = names(cmslite_name_map),
    .f = \(acc, nm) coalesce_aliases(acc, cmslite_name_map[[nm]], nm),
    .init = df
  )
}

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
      readr::read_csv(f, show_col_types = FALSE) |>
        janitor::clean_names(case = "snake") |>
        normalize_cmslite_names() |>
        dplyr::mutate(source_file = basename(f))
    }
  ) |>
    purrr::list_rbind()
}

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

analyze_google <- function(df) {
  list(
    top_queries = df |>
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

# Metric Definitions
# Impressions: The total number of times your ad or link was displayed on a screen.
# Clicks: The total number of times users actually clicked on the displayed link or ad.
# CTR: The ratio showing how often an impression results in a click.
